# Smart Contracts

The smart contracts in this directory implement Poon-Dryja state channels for use with Ethereum. See below for details describing how these contracts work.

## Directory Index

- **Lightning.sol**: Version of the contract for use with regular ETH transactions.
- **LightningERC20.sol**: Version of the contract for use with any ERC-20 compliant token.
- **BytesLib.sol**: A library implementing a set of useful conversions between Solidity types and bytes.
- **BytesBuffer.sol**: A library implementing a byte buffer.

## Lightning.sol Usage

Lightning.sol and LightningERC20.sol only differ in their deposit and withdrawal methods. We will first describe the functionality they have in common. For the sake of brevity, we will use 'Lightning.sol' to refer to both versions of the contract throughout this section.

Lightning.sol operates by 'packetizing' Ethereum transactions into a UTXO model equivalent to Bitcoin's. Outputs are created whenever coins are deposited or spent, and are destroyed when they are used as an input to another output or upon withdrawal. Outputs are identified by an `id` field of `uint` type, and can be looked up in the `outputs` mapping.

Outputs are spent by providing a set of signed witness and output scripts to the `spend` method. These scripts differ from Bitcoin Scripts in that they are not stack machines. Rather, a one-byte prefix denotes the script's type - for example, P2WPKH or multisig - and the smart contract uses the script as input to a contract method. See below for all supported scripts:

### P2WPKH

- Locking script:
	- prefix: `0x01`
	- data:
		- [`20: recipient address`]
- Witness script:
	- data:
		- [`1: 0x00`]
		- [`65: recipient signature`]

### Multisig

- Locking script:
	- prefix: `0x02`
	- data:
		- [`20: alice address`]
		- [`20: bob address`]
- Witness script:
	- data:
		- [`1: 0x00`]
		- [`65: alice sig`]
		- [`65: bob sig`]

### To Local Commitment

- Locking script:
	- prefix: `0x03`
	- data:
		- [`32: delay (in blocks)`]
		- [`20: delayed address`]
		- [`20: revocation address`]
- Witness script:
	- data:
		- [`1: 0x00 if to delayed, 0x01 if revocation`]
		- [`65: revocation or delayed signature`]

### Offered HTLCs

- Locking script:
	- prefix: `0x04`
	- data:
		- [`32: delay (in blocks)`]
		- [`20: redemption address`]
		- [`20: timeout address`]
		- [`32: payment hash`]
- Witness script:
	- data:
		- [`1: 0x00 if redemption, 0x01 if timeout`]
		- [`32 (only if redemption): redemption preimage`]
		- [`65 (only if timeout): signature`]

### Output Generation

To create an output for use in the `spend` method, concatenate the following data:

- [`32: value`]
- [`1: locking script prefix`]
- [`n: locking script`]
		
### Signature Generation

Signatures are generated by signing the `keccak256` hash of the data in the following list. All numbers are encoded as big-endian.

- [`32: output id`]
- [`witness script length: witness script`]
- [`32: outputs hash`]

To generate the outputs hash, concatenate and hash all outputs constructed as described in the Output Generation section.

