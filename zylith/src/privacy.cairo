// Privacy module - declares submodules
pub mod commitment;
pub mod deposit;
pub mod merkle_tree;
pub mod mock_verifier;
pub mod verifier;

pub mod verifiers {
    pub mod membership {
        pub mod groth16_verifier;
        pub mod groth16_verifier_constants;
    }

    pub mod swap {
        pub mod groth16_verifier;
        pub mod groth16_verifier_constants;
    }

    pub mod withdraw {
        pub mod groth16_verifier;
        pub mod groth16_verifier_constants;
    }

    pub mod lp {
        pub mod groth16_verifier;
        pub mod groth16_verifier_constants;
    }
}

pub use verifier::{IZKVerifier, IZKVerifierDispatcher, IZKVerifierDispatcherTrait};
