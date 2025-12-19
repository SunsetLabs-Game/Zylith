

# Zylith ZK Circuits – Setup

## 🛠 Prerequisites

* **Node.js** ≥ 16
* **Circom** ≥ 2.1
* **Garaga**
* **Git**

Verify:

```bash
node --version
circom --version
garaga --version
```

---

## 📦 Install Dependencies

```bash
npm install
```

---

## 🚀 Build Everything (Recommended)

```bash
npm run build-all
```

This will:

* Compile circuits
* Run trusted setup
* Generate proving & verification keys
* Export verification keys
* Generate Cairo verifiers

---

## 🔧 Manual Setup (Optional)

```bash
npm run compile
npm run setup
npm run generate-keys
npm run export-vk
npm run generate-garaga
```

---

## 📁 Output

```
build/        # r1cs, wasm
pot/          # powers of tau
zkeys/        # proving keys
vkeys/        # verification keys
src/privacy/  # Cairo verifiers
```

---

