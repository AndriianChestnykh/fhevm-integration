import {HardhatEthersSigner} from "@nomicfoundation/hardhat-ethers/signers";
import {ethers, fhevm} from "hardhat";
import {ERC20_mock, ERC4626_mock, UniversalPrivacyLayer} from "../types";
import {expect} from "chai";

type Signers = {
    owner: HardhatEthersSigner;
    user1: HardhatEthersSigner;
    user2: HardhatEthersSigner;
};

async function deployFixture(signers: Signers) {
    const erc20Token = await ethers.deployContract("ERC20_mock");
    await erc20Token.mint(signers.user1.address, 1000);
    await erc20Token.mint(signers.user2.address, 1000);

    const erc20TokenAddress = await erc20Token.getAddress();

    const erc4626Token = await ethers.deployContract("ERC4626_mock", [erc20TokenAddress]);
    const erc4626TokenAddress = await erc4626Token.getAddress();

    const privacyLayer = await ethers.deployContract(
        "UniversalPrivacyLayer",
        [
            erc20TokenAddress,
            erc4626TokenAddress,
            signers.owner.address,
        ],
        {
            signer: signers.owner,
        },
    );
    const privacyLayerAddress = await privacyLayer.getAddress();

    await erc20Token.connect(signers.user1).approve(privacyLayerAddress, 1000);
    await erc20Token.connect(signers.user2).approve(privacyLayerAddress, 1000);

    return {erc20Token, erc4626Token, privacyLayer, privacyLayerAddress};
}

describe("UniversalPrivacyResolver", function () {
    let signers: Signers;
    let privacyLayer: UniversalPrivacyLayer;
    let erc20Token: ERC20_mock;
    let erc4626Token: ERC4626_mock;
    let privacyLayerAddress: string;

    before(async function () {
        const ethSigners: HardhatEthersSigner[] = await ethers.getSigners();
        signers = {owner: ethSigners[0], user1: ethSigners[1], user2: ethSigners[2]};
    });

    beforeEach(async () => {
        // Check whether the tests are running against an FHEVM mock environment
        if (!fhevm.isMock) {
            throw new Error(`This hardhat test suite cannot run on Sepolia Testnet`);
        }
        ({erc20Token, erc4626Token, privacyLayer, privacyLayerAddress} = await deployFixture(signers));
    });

    it("users can deposit to privacy layer", async function () {
        await privacyLayer.connect(signers.user1).deposit(100);
        await privacyLayer.connect(signers.user2).deposit(100);
        expect(await erc20Token.balanceOf(privacyLayerAddress)).to.equal(200);
        await privacyLayer.connect(signers.user1).deposit(50);
        expect(await erc20Token.balanceOf(privacyLayerAddress)).to.equal(250);
    });

    it("users can init deposit to vault", async function () {
        const encryptedDepositUser1 = await fhevm
            .createEncryptedInput(privacyLayerAddress, signers.user1.address)
            .add128(10)
            .encrypt();

        const encryptedDepositUser2 = await fhevm
            .createEncryptedInput(privacyLayerAddress, signers.user2.address)
            .add128(20)
            .encrypt();

        await privacyLayer
            .connect(signers.user1)
            .depositToVault(
                encryptedDepositUser1.handles[0],
                encryptedDepositUser1.inputProof,
            )

        await privacyLayer
            .connect(signers.user2)
            .depositToVault(
                encryptedDepositUser2.handles[0],
                encryptedDepositUser2.inputProof,
            );
    });
});
