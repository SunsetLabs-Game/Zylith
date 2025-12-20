mod merkle;
mod syncer;

use ax_sessions::{Session, SessionManager};
use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::IntoResponse,
    routing::{get, post},
    Json, Router,
};
use merkle::{MerkleTree, TREE_DEPTH};
use std::sync::{Arc, Mutex};
use syncer::Syncer;
use serde::Serialize;

#[derive(Clone)]
struct AppState {
    tree: Arc<Mutex<MerkleTree>>,
}

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt::init();

    let tree = Arc::new(Mutex::new(MerkleTree::new(TREE_DEPTH)));
    let state = AppState { tree: tree.clone() };

    // Initialize Syncer
    // In production, these would come from env vars
    let rpc_url = "http://localhost:5050"; 
    let contract_address = "0x0123456789abcdef"; 
    
    let syncer = Syncer::new(rpc_url, contract_address, tree);
    
    // Run syncer in background
    tokio::spawn(async move {
        syncer.run().await;
    });

    let app = Router::new()
        .route("/proof/:index", get(get_proof))
        .route("/root", get(get_root))
        .with_state(state);

    let listener = tokio::net::TcpListener::bind("0.0.0.0:3000").await.unwrap();
    println!("ASP Server running on port 3000");
    axum::serve(listener, app).await.unwrap();
}

async fn get_proof(
    Path(index): Path<u32>,
    State(state): State<AppState>,
) -> impl IntoResponse {
    let tree = state.tree.lock().unwrap();
    if index >= tree.next_index {
        return (StatusCode::NOT_FOUND, "Index not yet synced").into_response();
    }

    let proof = tree.get_proof(index);
    Json(proof).into_response()
}

async fn get_root(
    State(state): State<AppState>,
) -> impl IntoResponse {
    let tree = state.tree.lock().unwrap();
    let root = tree.get_root();
    Json(format!("0x{:x}", root)).into_response()
}
