async function main() {
    const vaultContract = await ethers.getContractFactory("Vault");
    const bondhive_vault = await vaultContract.deploy();
    console.log("Contract Deployed to Address:", bondhive_vault.address);
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });