use crate::merkle::{MerkleTree, TREE_DEPTH};
use num_bigint::BigUint;
use starknet::{
    core::types::{BlockId, EventFilter, FieldElement},
    core::utils::starknet_keccak,
    providers::{jsonrpc::HttpTransport, JsonRpcClient, Provider},
};
use std::fs;
use std::sync::{Arc, Mutex};
use tokio::time::{sleep, Duration};
use url::Url;

/// Deposit event selector: starknet_keccak("Deposit")
/// This is the hash of the event name used to filter deposit events
/// Calculated as: starknet_keccak(b"Deposit") truncated to 250 bits
const DEPOSIT_EVENT_SELECTOR: &str =
    "0x9149d2123147c5f43d258257fef0b7b969db78269369ebcf5ebb9eef8592f2";

/// Calculate event selector from name
fn get_event_selector(name: &str) -> FieldElement {
    let hash = starknet_keccak(name.as_bytes());
    // Truncate to 250 bits (Starknet field element)
    hash & FieldElement::from_hex_be("0x3ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff").unwrap()
}

/// State file for persistence
const STATE_FILE: &str = "asp_state.json";

#[derive(serde::Serialize, serde::Deserialize, Default)]
struct SyncerState {
    last_synced_block: u64,
}

pub struct Syncer {
    pub provider: Arc<JsonRpcClient<HttpTransport>>,
    pub contract_address: FieldElement,
    pub tree: Arc<Mutex<MerkleTree>>,
    pub deposit_selector: FieldElement,
    pub swap_selector: FieldElement,
    pub pool_event_selector: FieldElement,
    pub blockchain_client: Option<Arc<crate::blockchain::BlockchainClient>>,
}

impl Syncer {
    pub fn new(rpc_url: &str, contract_address: &str, tree: Arc<Mutex<MerkleTree>>) -> Self {
        let provider = Arc::new(JsonRpcClient::new(HttpTransport::new(
            Url::parse(rpc_url).unwrap(),
        )));
        let contract_address = FieldElement::from_hex_be(contract_address).unwrap();
        let deposit_selector = FieldElement::from_hex_be(DEPOSIT_EVENT_SELECTOR).unwrap();
        
        // Calculate selectors for other events
        let swap_selector = get_event_selector("Swap");
        let pool_event_selector = get_event_selector("PoolEvent");

        Self {
            provider,
            contract_address,
            tree,
            deposit_selector,
            swap_selector,
            pool_event_selector,
            blockchain_client: None,
        }
    }

    pub fn with_blockchain_client(mut self, client: Arc<crate::blockchain::BlockchainClient>) -> Self {
        self.blockchain_client = Some(client);
        self
    }

    /// Load persisted state
    fn load_state() -> SyncerState {
        fs::read_to_string(STATE_FILE)
            .ok()
            .and_then(|s| serde_json::from_str(&s).ok())
            .unwrap_or_default()
    }

    /// Save state to file
    fn save_state(state: &SyncerState) {
        if let Ok(json) = serde_json::to_string(state) {
            let _ = fs::write(STATE_FILE, json);
        }
    }

    pub async fn run(&self) {
        let mut state = Self::load_state();
        
        // Check if we should force re-sync from a specific block
        if let Ok(reset_block_str) = std::env::var("RESYNC_FROM_BLOCK") {
            if let Ok(reset_block) = reset_block_str.parse::<u64>() {
                state.last_synced_block = reset_block;
                Self::save_state(&state);
            }
        }
        
        // If state file doesn't exist or last_synced_block is 0, start from block 0 (genesis)
        // This ensures we sync ALL events from the beginning
        if state.last_synced_block == 0 {
            state.last_synced_block = 0;
            Self::save_state(&state);
            println!("[Syncer] 🚀 Starting fresh sync from block 0 (genesis)");
        }
        
        // Check if tree is empty but contract has deposits
        let leaf_count = {
            let tree = self.tree.lock().unwrap();
            tree.get_leaf_count()
        };
        
        if leaf_count == 0 {
            if let Some(ref blockchain) = self.blockchain_client {
                match blockchain.get_merkle_root().await {
                    Ok(contract_root) if contract_root != "0x0" && contract_root != "0x0000000000000000000000000000000000000000000000000000000000000000" => {
                        // If contract has deposits but tree is empty, start from block 0 to sync everything
                        state.last_synced_block = 0;
                        Self::save_state(&state);
                        println!("[Syncer] 🚀 Contract has deposits but tree is empty - starting sync from block 0");
                    }
                    _ => {}
                }
            }
        }

        loop {
            // Reload state from file in each iteration to pick up resync requests
            // This allows the /deposit/resync endpoint to trigger immediate resync
            let current_state = Self::load_state();
            if current_state.last_synced_block < state.last_synced_block {
                // State file was reset to an earlier block - force resync
                println!("[Syncer] 🔄 Detected resync request - resetting to block {}", current_state.last_synced_block);
                state.last_synced_block = current_state.last_synced_block;
                
                // Clear the tree to force full resync
                {
                    let mut tree = self.tree.lock().unwrap();
                    *tree = MerkleTree::new(TREE_DEPTH); // Reset tree - use TREE_DEPTH constant
                }
            } else if current_state.last_synced_block != state.last_synced_block {
                // State was updated but not reset - just update our state
                state.last_synced_block = current_state.last_synced_block;
            }
            
            // TEMPORARILY DISABLED FOR DEBUGGING - Root check causes infinite loop
            // First, verify our tree root matches the contract
            // Do this check separately to avoid Send issues - must drop lock before await
            let _should_resync = if let Some(ref blockchain) = self.blockchain_client {
                // Get local root first (drop lock before await)
                let local_root = {
                    let tree = self.tree.lock().unwrap();
                    format!("0x{:x}", tree.get_root())
                };
                
                // Now await without holding the lock
                let contract_root_result = blockchain.get_merkle_root().await;
                
                match contract_root_result {
                    Ok(contract_root) => {
                        // Log comparison but don't resync for debugging
                        if contract_root != local_root {
                            println!("[Syncer] 🛑 Root mismatch detected (DEBUG MODE - resync disabled):");
                            println!("[Syncer]    Local root:     {}", local_root);
                            println!("[Syncer]    On-chain root: {}", contract_root);
                            
                            // Show tree status for debugging
                            let tree = self.tree.lock().unwrap();
                            let leaf_count = tree.get_leaf_count();
                            println!("[Syncer]    Tree has {} leaves", leaf_count);
                            drop(tree);
                        } else {
                            println!("[Syncer] ✅ Roots match: {}", local_root);
                        }
                        false // Don't resync in debug mode
                    }
                    Err(e) => {
                        eprintln!("[Syncer] ❌ Failed to get contract root: {:?}", e);
                        false
                    }
                }
            } else {
                false
            };

            // DISABLED FOR DEBUGGING - Uncomment to re-enable auto-resync
            /*
            // If root mismatch, do a full resync from block 0
            // This ensures we sync ALL deposits from the beginning
            if should_resync {
                let tree = self.tree.lock().unwrap();
                let leaf_count = tree.get_leaf_count();
                drop(tree);
                
                println!("[Syncer] 🔄 Root mismatch detected - starting full resync from block 0");
                println!("[Syncer]    Current tree has {} leaves", leaf_count);
                state.last_synced_block = 0; // Start from genesis to sync everything
                Self::save_state(&state);
                
                // Clear the tree to force full resync
                {
                    let mut tree = self.tree.lock().unwrap();
                    *tree = MerkleTree::new(TREE_DEPTH); // Reset tree - use TREE_DEPTH constant
                }
                println!("[Syncer] ✅ Tree cleared, will sync all events from block 0");
            }
            */

            match self.sync_events(state.last_synced_block).await {
                Ok(new_last_block) => {
                    if new_last_block > state.last_synced_block {
                        let old_block = state.last_synced_block;
                        state.last_synced_block = new_last_block;
                        Self::save_state(&state);
                        
                        // Log progress if we synced a significant number of blocks
                        if new_last_block - old_block > 100 {
                            let tree = self.tree.lock().unwrap();
                            let leaf_count = tree.get_leaf_count();
                            drop(tree);
                            println!("[Syncer] ✅ Synced from block {} to {} ({} leaves in tree)", 
                                old_block, new_last_block, leaf_count);
                        }
                    }
                }
                Err(e) => {
                    eprintln!("[Syncer] ❌ Sync error: {:?}", e);
                    // Continue trying - don't exit on error
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

        // Filter for events from our contract
        // Note: For nested enum events (Event::PrivacyEvent::Deposit), the Deposit selector
        // is in keys[2], not keys[0]. So we filter only by contract address and check
        // all keys in the loop below.
        let filter = EventFilter {
            from_block: Some(BlockId::Number(from_block + 1)),
            to_block: Some(BlockId::Number(latest_block)),
            address: Some(self.contract_address),
            keys: None, // Don't filter by keys - we'll check in the loop for nested events
        };

        let chunk_size = 1000;
        let mut continuation_token = None;
        let mut swap_events_seen = 0u32;
        let mut _total_events_seen = 0u32;
        let mut _is_first_page = true;

        loop {
            let events_page = self
                .provider
                .get_events(filter.clone(), continuation_token.clone(), chunk_size)
                .await?;
            
            _total_events_seen += events_page.events.len() as u32;
            
            for event in events_page.events {
                // For nested enum events (PrivacyEvent::Deposit), the structure is:
                // keys[0] = PrivacyEvent enum selector
                // keys[1] = Deposit variant selector (if nested)
                // OR keys[0] = Deposit selector (if direct)
                // Check all keys to find the Deposit variant selector
                let is_deposit_event = !event.keys.is_empty() && 
                    event.keys.iter().any(|key| *key == self.deposit_selector);
                
                // Check for PoolEvent enum (which contains Swap)
                // Structure: keys[0] = Event enum, keys[1] = PoolEvent enum, keys[2] = Swap variant
                let is_pool_event = !event.keys.is_empty() && 
                    event.keys.iter().any(|key| *key == self.pool_event_selector);
                
                // Check for Swap events - can be at keys[1] or keys[2] depending on nesting
                let is_swap_event = !event.keys.is_empty() && (
                    event.keys.iter().any(|key| *key == self.swap_selector) ||
                    (is_pool_event && event.keys.len() >= 2 && event.keys[1] == self.swap_selector) ||
                    (is_pool_event && event.keys.len() >= 3 && event.keys[2] == self.swap_selector)
                );
                
                // Only log swap events
                if !is_deposit_event {
                    if is_swap_event {
                        swap_events_seen += 1;
                        println!(
                            "[Syncer] 🔄 Swap event #{} detected: keys={:?}, data_len={}",
                            swap_events_seen,
                            event.keys.iter().map(|k| format!("0x{:x}", k)).collect::<Vec<_>>(),
                            event.data.len()
                        );
                        if event.data.len() >= 6 {
                            println!(
                                "  📊 Swap details: sender=0x{:x}, recipient=0x{:x}, amount0={:?}, amount1={:?}",
                                event.data[0], event.data[1], event.data[2], event.data[3]
                            );
                        }
                    }
                    continue;
                }
                
                // Skip verbose deposit event logging - only log summary

                // Parse Deposit event data:
                // For nested events, the data structure is:
                // data[0] = commitment (felt252)
                // data[1] = leaf_index (u32)
                // data[2] = root (felt252)
                if event.data.len() >= 3 {
                        let commitment_felt = event.data[0];
                    let leaf_index_felt = event.data[1];

                    // Convert to BigUint for our Merkle tree
                    let commitment = BigUint::from_bytes_be(&commitment_felt.to_bytes_be());
                    let leaf_index: u32 = {
                        let bytes = leaf_index_felt.to_bytes_be();
                        let mut arr = [0u8; 4];
                        let start = bytes.len().saturating_sub(4);
                        arr.copy_from_slice(&bytes[start..]);
                        u32::from_be_bytes(arr)
                    };

                    // Get zero leaf and current count before acquiring mutable lock
                    let (current_count, zero_leaf) = {
                        let tree = self.tree.lock().unwrap();
                        (tree.get_leaf_count(), tree.zeros[0].clone())
                    };

                    // Insert into our tree
                    let mut tree = self.tree.lock().unwrap();

                    // Handle gaps: if leaf_index is greater than current count, insert empty leaves
                    if leaf_index > current_count {
                        let gaps = leaf_index - current_count;
                        // Insert empty leaves (zeros) to fill the gap
                        for i in 0..gaps {
                            tree.insert_at_index(current_count + i, zero_leaf.clone());
                        }
                    } else if leaf_index < current_count {
                        // Check if this commitment already exists at this index
                        if let Some(existing_leaf) = tree.nodes.get(&(0, leaf_index)) {
                            if existing_leaf == &commitment {
                                // Skip silently - already processed
                                continue;
                            }
                        }
                    }

                    // Insert the commitment at the correct index
                    if leaf_index == current_count {
                        // Normal sequential insert
                        tree.insert(commitment.clone());
                    } else {
                        // Insert at specific index (filling gaps already handled above)
                        tree.insert_at_index(leaf_index, commitment.clone());
                    }
                    // Process silently - no logging
                }
            }

            continuation_token = events_page.continuation_token;
            if continuation_token.is_none() {
                break;
            }
        }

        // Only log if swap events were found
        if swap_events_seen > 0 {
            println!("[Syncer] 🔄 Found {} swap event(s)", swap_events_seen);
        }

        Ok(latest_block)
    }
}
