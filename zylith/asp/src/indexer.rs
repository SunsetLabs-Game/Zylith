// Event Indexer - Listen to Starknet events and maintain Merkle tree state

use anyhow::Result;
use starknet_rs::{
    core::types::{BlockId, EventFilter, EventsPage, FieldElement},
    providers::{Provider, SequencerGatewayProvider},
};
use tracing::{error, info};

pub struct Indexer {
    provider: SequencerGatewayProvider,
    last_processed_block: u64,
}

impl Indexer {
    pub async fn new() -> Result<Self> {
        // Connect to Starknet RPC
        let provider = SequencerGatewayProvider::new(
            starknet_rs::providers::sequencer::GatewayProvider::new(
                starknet_rs::providers::sequencer::Network::Testnet,
            ),
        );

        Ok(Self {
            provider,
            last_processed_block: 0, // TODO: Load from database
        })
    }

    pub async fn run(&self) -> Result<()> {
        info!("Starting event indexer...");

        loop {
            match self.process_blocks().await {
                Ok(_) => {
                    tokio::time::sleep(tokio::time::Duration::from_secs(5)).await;
                }
                Err(e) => {
                    error!("Error processing blocks: {}", e);
                    tokio::time::sleep(tokio::time::Duration::from_secs(10)).await;
                }
            }
        }
    }

    async fn process_blocks(&self) -> Result<()> {
        // TODO: Get latest block number
        // TODO: Process blocks from last_processed_block to latest
        // TODO: Filter for Deposit events
        // TODO: Update Merkle tree state
        // TODO: Save to database

        info!("Processing blocks...");
        Ok(())
    }

    async fn process_deposit_event(&self, event: &starknet_rs::core::types::EmittedEvent) {
        // TODO: Extract commitment, leaf_index, root from event
        // TODO: Update local Merkle tree
        // TODO: Store in database
        info!("Processing deposit event: {:?}", event);
    }
}

