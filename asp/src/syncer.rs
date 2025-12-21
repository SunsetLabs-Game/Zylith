use starknet::{
    core::types::{BlockId, BlockTag, EventFilter, FieldElement},
    providers::{jsonrpc::HttpTransport, JsonRpcClient, Provider},
};
use std::sync::{Arc, Mutex};
use crate::merkle::MerkleTree;
use num_bigint::BigUint;
use tokio::time::{sleep, Duration};

pub struct Syncer {
    pub provider: Arc<JsonRpcClient<HttpTransport>>,
    pub contract_address: FieldElement,
    pub tree: Arc<Mutex<MerkleTree>>,
}

impl Syncer {
    pub fn new(
        rpc_url: &str,
        contract_address: &str,
        tree: Arc<Mutex<MerkleTree>>,
    ) -> Self {
        let provider = Arc::new(JsonRpcClient::new(HttpTransport::new(
            url::Url::parse(rpc_url).unwrap(),
        )));
        let contract_address = FieldElement::from_hex_be(contract_address).unwrap();

        Self {
            provider,
            contract_address,
            tree,
        }
    }

    pub async fn run(&self) {
        let mut last_block = 0u64; // In production, load from DB

        loop {
            match self.sync_events(last_block).await {
                Ok(new_last_block) => {
                    last_block = new_last_block;
                }
                Err(e) => {
                    eprintln!("Sync error: {:?}", e);
                }
            }
            sleep(Duration::from_secs(5)).await;
        }
    }

    async fn sync_events(&self, from_block: u64) -> Result<u64, Box<dyn std::error::Error>> {
        let latest_block = self.provider.block_number().await?;
        if from_block >= latest_block {
            return Ok(from_block);
        }

        let filter = EventFilter {
            from_block: Some(BlockId::Number(from_block + 1)),
            to_block: Some(BlockId::Number(latest_block)),
            address: Some(self.contract_address),
            keys: None, // We filter manually or provide specific keys
        };

        let chunk_size = 1000;
        let mut continuation_token = None;

        loop {
            let events_page = self.provider.get_events(filter.clone(), continuation_token, chunk_size).await?;
            
            for event in events_page.events {
                // Process event
                // Key[0] is Event Name Hash
                // For Zylith: 
                // Deposit: selector!("Deposit")
                // NullifierSpent: selector!("NullifierSpent")
                
                let selector = event.keys[0];
                
                // Simplified event processing for MVP
                if event.keys.len() > 0 {
                    // Check if it's a deposit
                    // selector!("Deposit") = 0x...
                    // For now, let's assume any event with data[0] as commitment is a deposit
                    if event.data.len() >= 1 {
                        let commitment_felt = event.data[0];
                        let commitment_bu = BigUint::from_bytes_be(&commitment_felt.to_bytes_be());
                        
                        let mut tree = self.tree.lock().unwrap();
                        tree.insert(commitment_bu);
                        println!("Synced commitment at block {}", event.block_number);
                    }
                }
            }

            continuation_token = events_page.continuation_token;
            if continuation_token.is_none() {
                break;
            }
        }

        Ok(latest_block)
    }
}
