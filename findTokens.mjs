async function run() {
  const url = 'https://testnet.arcscan.app/api?module=account&action=tokentx&address=0xCb92534f3bA18280f55A8A4cbC2665B48B36B429';
  const res = await fetch(url);
  const data = await res.json();
  if (data.result && Array.isArray(data.result)) {
    const tokens = new Map();
    for (const tx of data.result) {
      if (tx.tokenSymbol) {
        tokens.set(tx.tokenSymbol, { address: tx.contractAddress, decimals: tx.tokenDecimal });
      }
    }
    console.log(tokens);
  }
}
run();
