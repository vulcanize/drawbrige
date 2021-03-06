pragma solidity 0.4.24;

import "./ERC20.sol";
import "./BytesLib.sol";
import "./BytesBuffer.sol";
import "zeppelin-solidity/contracts/ECRecovery.sol";

contract LightningERC20 {
    using BytesLib for bytes;
    using BytesBuffer for BytesBuffer.Buffer;
    
    bytes1 PAYMENT_SIGIL = 0x01;
    
    bytes1 MULTISIG_SIGIL = 0x02;
    
    bytes1 LOCAL_COMMIT_SIGIL = 0x03;
    
    bytes1 HTLC_OFFER_SIGIL = 0x04;
    
    bytes ZERO_SIG = new bytes(65);
    
    bytes ZERO_BYTES = new bytes(0);
    
    address ZERO_ADDRESS = address(0);
    
    bytes32 ZERO_BYTES32 = bytes32(0);
    
    address public tokenAddress;
    
    uint public depositId;
    
    struct Output {
        uint value;
        uint blockNum;
        bytes script;
        bytes32 id;
        bool exists;
    }
    
    mapping(bytes32 => Output) public outputs;
    
    event Withdrawal(address owner, uint value);
    
    event Create(uint value, uint blockNum, bytes script, bytes32 id);
    
    event Spend(bytes32 id);
    
    event DebugBytes(bytes b);
    
    event DebugBytes32(bytes32 b);
    
    event DebugUint(uint b);
    
    event DebugAddress(address a);
    
    event DebugBytes1(bytes1 a);
    
    constructor(address _tokenAddress) public {
        tokenAddress = _tokenAddress;
        depositId = 0;
    }
    
    function deposit(uint value) public {
        require(value > 0);
        
        ERC20 tokenContract = ERC20(tokenAddress);
        require(tokenContract.transferFrom(msg.sender, address(this), value));
        bytes memory script = paymentScript(msg.sender);
        
        Output memory out = Output(
            value,
            block.number,
            script,
            keccak256(abi.encodePacked(++depositId, value, 0)),
            true
        );
        
        outputs[out.id] = out;
        emitCreate(out);
    }
    
    function withdraw(bytes witness, address payer) public {
        require(witness.length == 114);
        (bytes32 _, uint totalInputValue) = processInputs(witness, ZERO_BYTES);
        ERC20 tokenContract = ERC20(tokenAddress);
        require(tokenContract.transfer(payer, totalInputValue));
        emit Withdrawal(payer, totalInputValue);
    }
    
    function spend(bytes witnesses, bytes outputScripts) public {
        (bytes32 inputsHash, uint totalInputValue) = processInputs(witnesses, outputScripts);
        
        // value (32), sigil(1), script (n)
        
        uint cursor = 0;
        uint totalOutputValue = 0;
        uint index = 0;
        
        while (cursor < outputScripts.length) {
            uint value = outputScripts.toUint(cursor);
            cursor += 32;
            bytes1 sigil = outputScripts[cursor];
            uint16 scriptLen = scriptLength(sigil);
            require(scriptLen > 0);
            require(outputScripts.length - cursor >= scriptLen);
            bytes memory script = outputScripts.slice(cursor, scriptLen);
            cursor += scriptLen;
            
            totalOutputValue += value;
            
            Output memory out = Output(
                value,
                block.number,
                script,
                keccak256(abi.encodePacked(inputsHash, script, value, index)),
                true
            );
            
            outputs[out.id] = out;
            emitCreate(out);
            index++;
        }
        
        require(totalInputValue == totalOutputValue);
    }
    
    function processInputs(bytes witnesses, bytes outputScripts) private returns (bytes32, uint) {
        uint cursor = 0;
        uint totalInputValue = 0;
        BytesBuffer.Buffer memory buf = BytesBuffer.Buffer(new bytes(64), 0);
        
        // outputid (32), witness
        while (cursor < witnesses.length) {
            bytes32 outputId = witnesses.slice32(cursor);
            buf.putBytes32(outputId);
            cursor += 32;
            uint16 witnessLen = witnesses.toUint16(cursor);
            cursor += 16;
            bytes memory witness = witnesses.slice(cursor, witnessLen);
            cursor += witnessLen;
            Output memory input = outputs[outputId];
            require(isSpendable(input, witness, outputScripts));
            totalInputValue += input.value;
            delete outputs[input.id];
            emit Spend(input.id);
        }
        
        return (keccak256(buf.trimmed()), totalInputValue);
    }
    
    function outputId(uint value, bytes script, bytes32 inputId) private returns (bytes32) {
        return keccak256(block.number, value, script, inputId);
    }
    
    function verify(bytes32 data, address expected, bytes sig) returns (bool) {
        return ECRecovery.recover(ECRecovery.toEthSignedMessageHash(data), sig) == expected;
    }
    
    function paymentScript(address redeemer) public returns (bytes) {
        BytesBuffer.Buffer memory buf = BytesBuffer.Buffer(new bytes(21), 0);
        buf.putByte(PAYMENT_SIGIL);
        buf.putAddress(redeemer);
        return buf.data;
    }
    
    function emitCreate(Output out) private {
        emit Create(out.value, out.blockNum, out.script, out.id);
    }
    
    function isSpendable(Output out, bytes witness, bytes outputScripts) private returns (bool) {
        bytes1 sigil = out.script[0];
        
        if (sigil == PAYMENT_SIGIL) {
            return isPaymentSpendable(out, witness, outputScripts);
        }
        
        if (sigil == MULTISIG_SIGIL) {
            return isMultisigSpendable(out, witness, outputScripts);
        }
        
        if (sigil == LOCAL_COMMIT_SIGIL) {
            return isLocalCommitSpendable(out, witness, outputScripts);
        }
        
        if (sigil == HTLC_OFFER_SIGIL) {
            return isHTLCOfferSpendable(out, witness, outputScripts);
        }
        
        return false;
    }
    
    function isPaymentSpendable(Output out, bytes witness, bytes outputScripts) private returns (bool) {
        bytes32 hash = keccak256(abi.encodePacked(out.id, witness.slice(0, 1), outputScripts));
        bytes memory sig = witness.slice(1, 65);
        address redeemer = out.script.toAddress(1);
        return verify(hash, redeemer, sig);
    }
    
    function isMultisigSpendable(Output out, bytes witness, bytes outputScripts) private returns (bool) {
        uint cursor = 0;
        bytes32 hash = keccak256(abi.encodePacked(out.id, witness.slice(0, 1), outputScripts));
        cursor += 1;
        bytes memory sigA = witness.slice(cursor, 65);
        cursor += 65;
        bytes memory sigB = witness.slice(cursor, 65);
        
        address partyA = out.script.toAddress(1);
        address partyB = out.script.toAddress(21);
        return verify(hash, partyA, sigA) && verify(hash, partyB, sigB);
    }
    
    function isLocalCommitSpendable(Output out, bytes witness, bytes outputScripts) private returns (bool) {
        bytes32 hash = keccak256(abi.encodePacked(out.id, witness.slice(0, 1), outputScripts));
        bytes1 txType = witness[0];
        bytes memory sig = witness.slice(1, 65);
        
        if (txType == 0x01) {
            address revocation = out.script.toAddress(53);
            return verify(hash, revocation, sig);
        }
        
        uint delay = out.script.toUint(1);
        if (out.blockNum + delay >= block.number) {
            return false;
        }
        
        address delayed = out.script.toAddress(33);
        return verify(hash, delayed, sig);
    }
    
    function isHTLCOfferSpendable(Output out, bytes witness, bytes outputScripts) private returns (bool) {
        bytes1 txType = witness[0];
        
        if (txType == 0x00) {
            address redemption = out.script.toAddress(33);
            bytes32 preimage = witness.slice32(1);
            bytes32 expectedHash = out.script.slice32(73);
            // TODO: use signature verification to allow delegated spends
            return sha256(preimage) == expectedHash && msg.sender == redemption;
        }
        
        // 0x01 for timeout
        if (txType != 0x01) {
            return true;
        }
        
        uint delay = out.script.toUint(1);
        if (out.blockNum + delay >= block.number) {
            return false;
        }
        
        address timeout = out.script.toAddress(53);
        bytes32 hash = keccak256(abi.encodePacked(out.id, witness.slice(0, 1)));
        bytes memory sig = witness.slice(1, 65);
        return verify(hash, timeout, sig);
    }
    
    function scriptLength(bytes1 sigil) public returns (uint16) {
        if (sigil == PAYMENT_SIGIL) {
            return 21;
        }
        
        if (sigil == MULTISIG_SIGIL) {
            return 41;
        }
        
        if (sigil == LOCAL_COMMIT_SIGIL) {
            return 73;
        }
        
        if (sigil == HTLC_OFFER_SIGIL) {
            return 105;
        }
        
        return 0;
    }
}