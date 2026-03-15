// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseNFT, BaseNFTParams} from "./Base/BaseNFTNativePaymentToken.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {OApp, Origin, MessagingFee, MessagingReceipt} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {OAppOptionsType3} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OAppOptionsType3.sol";
import {IONFT721, SendParam} from "@layerzerolabs/onft-evm/contracts/onft721/interfaces/IONFT721.sol";
import {ONFT721MsgCodec} from "@layerzerolabs/onft-evm/contracts/onft721/libs/ONFT721MsgCodec.sol";
import {ONFTComposeMsgCodec} from "@layerzerolabs/onft-evm/contracts/libs/ONFTComposeMsgCodec.sol";

/**
 * @title BaseNFTOmnichain
 * @notice Combines BaseNFT (ERC721AC) minting with LayerZero OApp for cross-chain transfers.
 * @dev Uses composition: inherits BaseNFT for the token + OApp for LZ messaging,
 *      avoiding the diamond-inheritance conflict between ERC721AC and ONFT721's ERC721.
 *      Implements IONFT721 for ecosystem compatibility.
 */
contract BaseNFTOmnichain is BaseNFT, OApp, OAppOptionsType3, IONFT721 {
    using ONFT721MsgCodec for bytes;
    using ONFT721MsgCodec for bytes32;

    uint16 public constant SEND = 1;
    uint16 public constant SEND_AND_COMPOSE = 2;

    error InvalidEndpoint();

    constructor(
        BaseNFTParams.InitParams memory _params,
        address _lzEndpoint,
        address _delegate
    )
        BaseNFT(_params)
        OApp(_lzEndpoint, _delegate)
    {
        if (_lzEndpoint == address(0)) revert InvalidEndpoint();
    }

    // ─── IONFT721 Interface ──────────────────────────────────────────────────

    function onftVersion() external pure returns (bytes4, uint64) {
        return (type(IONFT721).interfaceId, 1);
    }

    function token() external view returns (address) {
        return address(this);
    }

    function approvalRequired() external pure returns (bool) {
        return false;
    }

    function quoteSend(
        SendParam calldata _sendParam,
        bool _payInLzToken
    ) external view returns (MessagingFee memory) {
        (bytes memory message, bytes memory options) = _buildMsgAndOptions(_sendParam);
        return _quote(_sendParam.dstEid, message, options, _payInLzToken);
    }

    function send(
        SendParam calldata _sendParam,
        MessagingFee calldata _fee,
        address _refundAddress
    ) external payable returns (MessagingReceipt memory msgReceipt) {
        _debit(msg.sender, _sendParam.tokenId, _sendParam.dstEid);

        (bytes memory message, bytes memory options) = _buildMsgAndOptions(_sendParam);
        msgReceipt = _lzSend(_sendParam.dstEid, message, options, _fee, _refundAddress);

        emit ONFTSent(msgReceipt.guid, _sendParam.dstEid, msg.sender, _sendParam.tokenId);
    }

    // ─── Internal: Message Building ──────────────────────────────────────────

    function _buildMsgAndOptions(
        SendParam calldata _sendParam
    ) internal view returns (bytes memory message, bytes memory options) {
        if (_sendParam.to == bytes32(0)) revert InvalidReceiver();

        bool hasCompose;
        (message, hasCompose) = ONFT721MsgCodec.encode(
            _sendParam.to,
            _sendParam.tokenId,
            _sendParam.composeMsg
        );

        uint16 msgType = hasCompose ? SEND_AND_COMPOSE : SEND;
        options = combineOptions(_sendParam.dstEid, msgType, _sendParam.extraOptions);
    }

    // ─── Internal: LayerZero Receive ─────────────────────────────────────────

    function _lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address,
        bytes calldata
    ) internal override {
        address toAddress = _message.sendTo().bytes32ToAddress();
        uint256 tokenId_ = _message.tokenId();

        _credit(toAddress, tokenId_, _origin.srcEid);

        if (_message.isComposed()) {
            bytes memory composeMsg = ONFTComposeMsgCodec.encode(
                _origin.nonce,
                _origin.srcEid,
                _message.composeMsg()
            );
            endpoint.sendCompose(toAddress, _guid, 0, composeMsg);
        }

        emit ONFTReceived(_guid, _origin.srcEid, toAddress, tokenId_);
    }

    // ─── Internal: Debit / Credit ────────────────────────────────────────────

    function _debit(address _from, uint256 _tokenId, uint32) internal {
        address tokenOwner = ownerOf(_tokenId);
        if (tokenOwner != _from) revert OnlyNFTOwner(_from, tokenOwner);
        _burn(_tokenId);
    }

    function _credit(address _to, uint256, uint32) internal {
        _safeMint(_to, 1);
    }

    // ─── View ────────────────────────────────────────────────────────────────

    function isOwnerOrApproved(
        address _owner,
        address _spender,
        uint256 _tokenId
    ) public view returns (bool) {
        return _owner == _spender ||
            getApproved(_tokenId) == _spender ||
            isApprovedForAll(_owner, _spender);
    }

    function getEndpoint() external view returns (address) {
        return address(endpoint);
    }

    function getPeer(uint32 _eid) external view returns (bytes32) {
        return peers[_eid];
    }

    // ─── Override Resolution ─────────────────────────────────────────────────

    function owner()
        public
        view
        override(Ownable)
        returns (address)
    {
        return Ownable.owner();
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override returns (bool) {
        return
            interfaceId == type(IONFT721).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    // ─── Receive (for LZ fees) ───────────────────────────────────────────────

    receive() external payable {}
}
