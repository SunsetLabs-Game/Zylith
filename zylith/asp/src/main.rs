// Zylith ASP - Association Set Provider
// Off-chain service for Merkle tree path reconstruction

use axum::{routing::get, Router};
use std::net::SocketAddr;
use tracing::info;

mod api;
mod indexer;
mod merkle;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Initialize tracing
    tracing_subscriber::fmt::init();

    info!("Starting Zylith ASP...");

    // Initialize indexer
    let indexer = indexer::Indexer::new().await?;
    
    // Start indexer in background
    let indexer_handle = tokio::spawn(async move {
        indexer.run().await
    });

    // Setup API routes
    let app = Router::new()
        .route("/health", get(api::health))
        .route("/merkle-path/:commitment", get(api::get_merkle_path))
        .route("/root", get(api::get_root));

    let addr = SocketAddr::from(([0, 0, 0, 0], 3000));
    info!("ASP API listening on {}", addr);

    // Run server
    axum::Server::bind(&addr)
        .serve(app.into_make_service())
        .await?;

    // Wait for indexer (this won't be reached in normal operation)
    let _ = indexer_handle.await;

    Ok(())
}
