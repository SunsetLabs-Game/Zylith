// REST API - Serve Merkle paths and tree state

use axum::{extract::Path, http::StatusCode, response::Json};
use serde::{Deserialize, Serialize};

#[derive(Serialize)]
struct HealthResponse {
    status: String,
}

#[derive(Serialize)]
struct MerklePathResponse {
    path: Vec<String>,
    root: String,
    leaf_index: u32,
}

#[derive(Serialize)]
struct RootResponse {
    root: String,
}

pub async fn health() -> Json<HealthResponse> {
    Json(HealthResponse {
        status: "ok".to_string(),
    })
}

pub async fn get_merkle_path(
    Path(commitment): Path<String>,
) -> Result<Json<MerklePathResponse>, StatusCode> {
    // TODO: Lookup commitment in database
    // TODO: Get Merkle path from tree
    // TODO: Return path and root

    Ok(Json(MerklePathResponse {
        path: Vec::new(),
        root: "0x0".to_string(),
        leaf_index: 0,
    }))
}

pub async fn get_root() -> Json<RootResponse> {
    // TODO: Get current root from database/tree
    Json(RootResponse {
        root: "0x0".to_string(),
    })
}

