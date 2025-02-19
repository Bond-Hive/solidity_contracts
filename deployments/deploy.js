async function main() {
    const vaultContract = await ethers.getContractFactory("Vault");
    const bondhive_vault = await vaultContract.deploy("0x74D617F3F9765315eCF5B1D1CFC12f31faeE30Ed","BondHive bond BTC24","bBTC24");
    console.log("Contract Deployed to Address:", bondhive_vault.address);
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });