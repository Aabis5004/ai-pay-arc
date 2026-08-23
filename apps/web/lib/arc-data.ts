export const arcDocsContext = `Background facts about Arc (use these to answer user questions):
- Arc is an open Layer-1 blockchain purpose-built for programmable money.
- USDC is the native gas token. Configure gas payment in USDC when submitting transactions.
- It features sub-second deterministic finality (transactions are final in under 1 second), EVM compatibility, opt-in privacy, and direct integration with Circle's full-stack platform.
- The platform uses App Kit for bridging, swaps, and unified balance capabilities. Unified Balance combines USDC from multiple chains into a single spendable balance.
- Arc is currently available on Testnet only. You can get testnet tokens from the Circle Faucet.
- Use cases: global payments, exchanges, lending, scalable finance.
- "AI Pay Arc" (this app) is a payments demo: deposit native USDC into a vault, send instant transfers on the Arc Testnet.
- Opt-in Privacy: APS uses a single master secret key (MSK) distributed across validators through Shamir threshold secret sharing. The MSK can only be reconstructed inside attested enclaves and is never exposed to validator hosts. All derived keys for transaction decryption, per-contract state encryption, and state root encryption come from the MSK.

About Arc House & Community:
- Arc House is a global network of builders developing the Economic OS for the internet. Reimagining how value moves, creating the tools that make that economy work for everyone.
- Builders earn points and register AI Agents.
- There is a "Arc x Chainlink: Data and Interoperability for Financial Applications" event on Aug 27, 2026 at 10AM ET featuring Sam Sealey (Director, Community, Developer & Ecosystem Marketing, Circle) and Dave Ishitski (Chief DevRel Engineer, Chainlink Labs).
- There is an "Office Hours" bi-weekly series starting soon.

Developer Guide:
1. USDC is the gas token.
2. EVM compatible (use standard tools like Hardhat, Foundry, Viem, Ethers).
3. Sub-second finality.
4. Use App Kit for bridging, swaps, and unified balance.
5. AI and Agents on Arc:
   - Arc MCP Server: Connect AI tools to Arc documentation via MCP
   - Agentic Economy: Onchain identity and job settlement for AI agents
   - Register an AI Agent: ERC-8004 onchain identity and reputation
   - Create an ERC-8183 Job: Escrow, deliverables, settlement
`;
