// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Ciskoi Wallet - Contrato inteligente de billetera descentralizada en Ethereum
/// @author Elser Manuel
/// @notice Este contrato permite enviar, recibir y gestionar ETH de forma segura.
/// @dev Solo el propietario puede retirar fondos. Todas las transacciones quedan registradas en eventos.

contract CiskoiWallet {
    address public owner;

    /// @notice Evento que registra un depósito de ETH en la billetera
    /// @param sender Dirección que envía el ETH
    /// @param amount Cantidad de ETH recibida (en wei)
    event Deposit(address indexed sender, uint amount);

    /// @notice Evento que registra un envío de ETH desde la billetera
    /// @param receiver Dirección que recibe el ETH
    /// @param amount Cantidad de ETH enviada (en wei)
    event Transfer(address indexed receiver, uint amount);

    /// @notice Se asigna como propietario a quien despliega el contrato
    constructor() payable {
        require(msg.value >= 0, "Puede enviar ETH opcionalmente al crear");
        owner = msg.sender;

        if (msg.value > 0) {
            emit Deposit(msg.sender, msg.value);
        }
    }

    /// @notice Función que permite recibir ETH en el contrato (función especial `receive`)
    receive() external payable {
        emit Deposit(msg.sender, msg.value);
    }

    /// @notice Devuelve el saldo actual en el contrato inteligente
    /// @return balance ETH disponible en wei
    function getBalance() external view returns (uint) {
        return address(this).balance;
    }

    /// @notice Permite al propietario enviar ETH a otra dirección
    /// @dev La función verifica que el emisor sea el propietario y que haya saldo suficiente
    /// @param _to Dirección a la que se enviará el ETH
    /// @param _amount Cantidad de ETH a transferir en wei
    function sendEther(address payable _to, uint _amount) external {
        require(msg.sender == owner, "No tienes permiso para enviar fondos");
        require(_amount > 0, "La cantidad debe ser mayor que cero");
        require(address(this).balance >= _amount, "Saldo insuficiente");

        (bool success, ) = _to.call{value: _amount}("");
        require(success, "Fallo en la transferencia");

        emit Transfer(_to, _amount);
    }
}
