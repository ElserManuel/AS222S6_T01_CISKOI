// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Ciskoi Wallet - Contrato inteligente de billetera descentralizada en Ethereum
 * @author Elser Manuel
 * @notice Este contrato permite administrar ETH de forma segura con características adicionales de seguridad
 * @dev Implementa sistema de límites diarios, multifirma opcional y registro detallado de transacciones
 */
contract CiskoiWallet {
    // Variables de estado
    address public owner;
    address public backupOwner;
    uint public dailyLimit;
    uint public dailySpent;
    uint public lastResetDay;
    bool public multiSigEnabled;
    
    // Mapeo para almacenar las direcciones aprobadas
    mapping(address => bool) public approvedAddresses;
    
    // Estructura para el registro de transacciones
    struct Transaction {
        address to;
        uint256 amount;
        uint256 timestamp;
        string description;
        bool executed;
    }
    
    // Registro de transacciones
    Transaction[] public transactionHistory;
    
    // Eventos
    /**
     * @notice Evento que registra un depósito de ETH en la billetera
     * @param sender Dirección que envía el ETH
     * @param amount Cantidad de ETH recibida (en wei)
     * @param balance Saldo actualizado después del depósito
     */
    event Deposit(address indexed sender, uint amount, uint balance);
    
    /**
     * @notice Evento que registra un envío de ETH desde la billetera
     * @param receiver Dirección que recibe el ETH
     * @param amount Cantidad de ETH enviada (en wei)
     * @param description Descripción opcional de la transacción
     * @param transactionId ID de la transacción en el historial
     */
    event Transfer(address indexed receiver, uint amount, string description, uint transactionId);
    
    /**
     * @notice Evento que registra un cambio en la configuración de la billetera
     * @param changedBy Dirección que realizó el cambio
     * @param settingName Nombre de la configuración cambiada
     * @param newValue Nuevo valor (codificado como bytes)
     */
    event SettingChanged(address indexed changedBy, string settingName, bytes newValue);
    
    /**
     * @notice Evento que registra la aprobación de una dirección para transacciones multifirma
     * @param approver Dirección que realiza la aprobación
     * @param approved Dirección aprobada
     * @param status Estado de aprobación (true/false)
     */
    event AddressApprovalChanged(address indexed approver, address indexed approved, bool status);
    
    // Modificadores
    /**
     * @notice Verifica que solo el propietario pueda ejecutar la función
     */
    modifier onlyOwner() {
        require(msg.sender == owner, "CiskoiWallet: Solo el propietario puede ejecutar esta operacion");
        _;
    }
    
    /**
     * @notice Verifica que solo el propietario o el propietario de respaldo puedan ejecutar la función
     */
    modifier onlyAuthorized() {
        require(msg.sender == owner || msg.sender == backupOwner, "CiskoiWallet: No estas autorizado");
        _;
    }
    
    /**
     * @notice Se asigna como propietario a quien despliega el contrato
     * @dev Inicializa los límites diarios y otras configuraciones
     */
    constructor() payable {
        require(msg.value >= 0, "CiskoiWallet: Puede enviar ETH opcionalmente al crear");
        owner = msg.sender;
        backupOwner = address(0);
        dailyLimit = type(uint).max; // Sin límite por defecto
        dailySpent = 0;
        lastResetDay = block.timestamp / 1 days;
        multiSigEnabled = false;
        
        if (msg.value > 0) {
            emit Deposit(msg.sender, msg.value, address(this).balance);
        }
    }
    
    /**
     * @notice Función que permite recibir ETH en el contrato
     * @dev Emite evento de depósito con información adicional
     */
    receive() external payable {
        emit Deposit(msg.sender, msg.value, address(this).balance);
    }
    
    /**
     * @notice Función alternativa para recibir ETH con datos
     * @dev Permite recibir ETH con información adicional en la transacción
     */
    fallback() external payable {
        emit Deposit(msg.sender, msg.value, address(this).balance);
    }
    
    /**
     * @notice Devuelve el saldo actual en el contrato inteligente
     * @return balance ETH disponible en wei
     */
    function getBalance() external view returns (uint) {
        return address(this).balance;
    }
    
    /**
     * @notice Reinicia el contador diario si es un nuevo día
     * @dev Función interna para gestionar los límites diarios
     */
    function _checkAndResetDailyLimit() internal {
        uint currentDay = block.timestamp / 1 days;
        if (currentDay > lastResetDay) {
            lastResetDay = currentDay;
            dailySpent = 0;
        }
    }
    
    /**
     * @notice Permite al propietario enviar ETH a otra dirección
     * @dev Verifica límites diarios y actualiza el historial de transacciones
     * @param _to Dirección a la que se enviará el ETH
     * @param _amount Cantidad de ETH a transferir en wei
     * @param _description Descripción opcional de la transacción
     * @return transactionId ID de la transacción en el historial
     */
    function sendEther(address payable _to, uint _amount, string memory _description) external onlyAuthorized returns (uint) {
        require(_to != address(0), "CiskoiWallet: Direccion de destino invalida");
        require(_amount > 0, "CiskoiWallet: La cantidad debe ser mayor que cero");
        require(address(this).balance >= _amount, "CiskoiWallet: Saldo insuficiente");
        
        _checkAndResetDailyLimit();
        require(dailySpent + _amount <= dailyLimit, "CiskoiWallet: Excede el limite diario");
        
        // Si multifirma está habilitada y no es el propietario principal
        if (multiSigEnabled && msg.sender != owner) {
            require(approvedAddresses[msg.sender], "CiskoiWallet: Direccion no aprobada para multifirma");
        }
        
        // Actualizar el contador diario
        dailySpent += _amount;
        
        // Crear y almacenar el registro de transacción
        uint transactionId = transactionHistory.length;
        transactionHistory.push(Transaction({
            to: _to,
            amount: _amount,
            timestamp: block.timestamp,
            description: _description,
            executed: false
        }));
        
        // Ejecutar la transferencia
        (bool success, ) = _to.call{value: _amount}("");
        require(success, "CiskoiWallet: Fallo en la transferencia");
        
        // Actualizar el estado de la transacción
        transactionHistory[transactionId].executed = true;
        
        // Emitir evento
        emit Transfer(_to, _amount, _description, transactionId);
        
        return transactionId;
    }
    
    /**
     * @notice Permite al propietario establecer un límite diario de gasto
     * @param _limit Nuevo límite diario en wei
     */
    function setDailyLimit(uint _limit) external onlyOwner {
        dailyLimit = _limit;
        emit SettingChanged(msg.sender, "dailyLimit", abi.encode(_limit));
    }
    
    /**
     * @notice Permite al propietario configurar un propietario de respaldo
     * @param _backupOwner Dirección del propietario de respaldo
     */
    function setBackupOwner(address _backupOwner) external onlyOwner {
        require(_backupOwner != address(0), "CiskoiWallet: Direccion de respaldo invalida");
        backupOwner = _backupOwner;
        emit SettingChanged(msg.sender, "backupOwner", abi.encode(_backupOwner));
    }
    
    /**
     * @notice Activa o desactiva la funcionalidad de multifirma
     * @param _enabled Estado de la funcionalidad multifirma
     */
    function setMultiSigEnabled(bool _enabled) external onlyOwner {
        multiSigEnabled = _enabled;
        emit SettingChanged(msg.sender, "multiSigEnabled", abi.encode(_enabled));
    }
    
    /**
     * @notice Aprueba o desaprueba una dirección para transacciones multifirma
     * @param _address Dirección a aprobar o desaprobar
     * @param _approved Estado de aprobación
     */
    function approveAddress(address _address, bool _approved) external onlyOwner {
        require(_address != address(0), "CiskoiWallet: Direccion invalida");
        approvedAddresses[_address] = _approved;
        emit AddressApprovalChanged(msg.sender, _address, _approved);
    }
    
    /**
     * @notice Devuelve el historial completo de transacciones
     * @return Arreglo de todas las transacciones realizadas
     */
    function getTransactionHistory() external view returns (Transaction[] memory) {
        return transactionHistory;
    }
    
    /**
     * @notice Función de emergencia que permite al propietario transferir todos los fondos
     * @param _to Dirección a la que se transferirán los fondos
     */
    function emergencyWithdraw(address payable _to) external onlyOwner {
        require(_to != address(0), "CiskoiWallet: Direccion de destino invalida");
        uint balance = address(this).balance;
        require(balance > 0, "CiskoiWallet: No hay fondos para retirar");
        
        // Crear y almacenar el registro de transacción
        uint transactionId = transactionHistory.length;
        transactionHistory.push(Transaction({
            to: _to,
            amount: balance,
            timestamp: block.timestamp,
            description: "Retiro de emergencia",
            executed: false
        }));
        
        // Ejecutar la transferencia
        (bool success, ) = _to.call{value: balance}("");
        require(success, "CiskoiWallet: Fallo en la transferencia de emergencia");
        
        // Actualizar el estado de la transacción
        transactionHistory[transactionId].executed = true;
        
        // Emitir evento
        emit Transfer(_to, balance, "Retiro de emergencia", transactionId);
    }
}