mod merkle;
mod syncer;

use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::IntoResponse,
    routing::{get, post},
    Json, Router,
};
use merkle::{MerkleTree, TREE_DEPTH};
use serde::{Deserialize, Serialize};
use std::sync::{Arc, Mutex};
use syncer::Syncer;

/// Application state with two Merkle trees
#[derive(Clone)]
struct AppState {
    /// Tree for deposit commitments (from on-chain events)
    deposit_tree: Arc<Mutex<MerkleTree>>,
    /// Tree for associated set (for compliance/subset proofs)
    associated_tree: Arc<Mutex<MerkleTree>>,
}

/// Response for tree info
#[derive(Serialize)]
struct TreeInfo {
    root: String,
    leaf_count: u32,
    depth: usize,
}

/// Request to insert into associated set
#[derive(Deserialize)]
struct InsertRequest {
    commitment: String,
}

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt::init();

    // Initialize both trees
    let deposit_tree = Arc::new(Mutex::new(MerkleTree::new(TREE_DEPTH)));
    let associated_tree = Arc::new(Mutex::new(MerkleTree::new(TREE_DEPTH)));

    let state = AppState {
        deposit_tree: deposit_tree.clone(),
        associated_tree: associated_tree.clone(),
    };

    // Initialize Syncer for deposit tree
    // In production, these would come from env vars
    let rpc_url = std::env::var("RPC_URL").unwrap_or_else(|_| "http://localhost:5050".to_string());
    let contract_address =
        std::env::var("CONTRACT_ADDRESS").unwrap_or_else(|_| "0x0123456789abcdef".to_string());
    
    let syncer = Syncer::new(&rpc_url, &contract_address, deposit_tree);
    
    // Run syncer in background
    tokio::spawn(async move {
        syncer.run().await;
    });

    let app = Router::new()
        // Deposit tree endpoints
        .route("/deposit/proof/:index", get(get_deposit_proof))
        .route("/deposit/root", get(get_deposit_root))
        .route("/deposit/info", get(get_deposit_info))
        // Associated set tree endpoints
        .route("/associated/proof/:index", get(get_associated_proof))
        .route("/associated/root", get(get_associated_root))
        .route("/associated/info", get(get_associated_info))
        .route("/associated/insert", post(insert_associated))
        // Legacy endpoints (for backwards compatibility)
        .route("/proof/:index", get(get_deposit_proof))
        .route("/root", get(get_deposit_root))
        // Health check
        .route("/health", get(health_check))
        .with_state(state);

    let port = std::env::var("PORT").unwrap_or_else(|_| "3000".to_string());
    let addr = format!("0.0.0.0:{}", port);

    let listener = tokio::net::TcpListener::bind(&addr).await.unwrap();
    println!("ASP Server running on {}", addr);
    println!("Endpoints:");
    println!("  GET  /deposit/proof/:index  - Get Merkle proof for deposit");
    println!("  GET  /deposit/root          - Get current deposit tree root");
    println!("  GET  /deposit/info          - Get deposit tree info");
    println!("  GET  /associated/proof/:index - Get Merkle proof for associated set");
    println!("  GET  /associated/root       - Get current associated set root");
    println!("  GET  /associated/info       - Get associated set tree info");
    println!("  POST /associated/insert     - Insert commitment into associated set");
    println!("  GET  /health                - Health check");

    axum::serve(listener, app).await.unwrap();
}

// ==================== Deposit Tree Endpoints ====================

async fn get_deposit_proof(
    Path(index): Path<u32>,
    State(state): State<AppState>,
) -> impl IntoResponse {
    let tree = state.deposit_tree.lock().unwrap();

    match tree.get_proof(index) {
        Some(proof) => Json(proof).into_response(),
        None => (StatusCode::NOT_FOUND, "Leaf not found at index").into_response(),
    }
}

async fn get_deposit_root(State(state): State<AppState>) -> impl IntoResponse {
    let tree = state.deposit_tree.lock().unwrap();
    let root = tree.get_root();
    Json(format!("0x{:x}", root))
}

async fn get_deposit_info(State(state): State<AppState>) -> impl IntoResponse {
    let tree = state.deposit_tree.lock().unwrap();
    Json(TreeInfo {
        root: format!("0x{:x}", tree.get_root()),
        leaf_count: tree.get_leaf_count(),
        depth: tree.depth,
    })
}

// ==================== Associated Set Endpoints ====================

async fn get_associated_proof(
    Path(index): Path<u32>,
    State(state): State<AppState>,
) -> impl IntoResponse {
    let tree = state.associated_tree.lock().unwrap();

    match tree.get_proof(index) {
        Some(proof) => Json(proof).into_response(),
        None => (StatusCode::NOT_FOUND, "Leaf not found at index").into_response(),
    }
}

async fn get_associated_root(State(state): State<AppState>) -> impl IntoResponse {
    let tree = state.associated_tree.lock().unwrap();
    let root = tree.get_root();
    Json(format!("0x{:x}", root))
}

async fn get_associated_info(State(state): State<AppState>) -> impl IntoResponse {
    let tree = state.associated_tree.lock().unwrap();
    Json(TreeInfo {
        root: format!("0x{:x}", tree.get_root()),
        leaf_count: tree.get_leaf_count(),
        depth: tree.depth,
    })
}

/// Insert a commitment into the associated set tree
/// This is used by operators to build compliance sets
async fn insert_associated(
    State(state): State<AppState>,
    Json(payload): Json<InsertRequest>,
) -> impl IntoResponse {
    use num_bigint::BigUint;
    use num_traits::Num;

    // Parse commitment from hex string
    let commitment_str = payload.commitment.trim_start_matches("0x");
    let commitment = match BigUint::from_str_radix(commitment_str, 16) {
        Ok(c) => c,
        Err(_) => {
            return (StatusCode::BAD_REQUEST, "Invalid commitment format").into_response()
        }
    };

    let mut tree = state.associated_tree.lock().unwrap();
    let new_root = tree.insert(commitment);
    let leaf_index = tree.get_leaf_count() - 1;

    Json(serde_json::json!({
        "success": true,
        "leaf_index": leaf_index,
        "new_root": format!("0x{:x}", new_root)
    }))
    .into_response()
}

// ==================== Health Check ====================

async fn health_check() -> impl IntoResponse {
    Json(serde_json::json!({
        "status": "ok",
        "version": "0.1.0"
    }))
}
