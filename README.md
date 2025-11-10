## 🏦 KipuBankV3
KipuBankV3 es un contrato inteligente de vault (bóveda) multi-activo para la red Ethereum. Este proyecto evoluciona el concepto de KipuBankV2 hacia una bóveda de contabilidad unificada.

El contrato gestiona depósitos de ETH nativo y tokens ERC20, convirtiéndolos automáticamente a USDC a través de Uniswap V2. El contrato mantiene todo su balance interno en USDC, lo que simplifica la contabilidad. Mantiene el control de acceso de OpenZeppelin y los mecanismos de pausa de emergencia.

### 📈 Explicación de Mejoras

- 🏧 Contabilidad Unificada en USDC
Todos los depósitos (ya sea ETH, WETH, u otros ERC20) se intercambian (swappean) automáticamente a USDC en el momento del depósito. El vault solo almacena USDC, y los balances de los usuarios se acreditan en USDC.

Esto resuelve conflictos entre el valor histórico de un depósito y el valor actual del activo. La contabilidad es 1 a 1 en USDC, eliminando el riesgo de fondos bloqueados (por underflow en retiros) o corrupción de saldos.

- 🔄 Integración con Uniswap V2
Se integra IUniswapV2Router02 para manejar todos los swaps de entrada. 
Esto permite al banco aceptar una gran variedad de tokens sin necesidad de gestionarlos internamente.

- 🛡️ Seguridad y Optimización Mantenidas
Se preservan (y mejoran) los patrones de seguridad y eficiencia:

Control de Acceso: Uso de AccessControl de OpenZeppelin con un ADMIN_ROLE para funciones críticas (como pause).

Protección Anti-Reentrada: Se aplica reentrancyGuard a todas las funciones de depósito y retiro para prevenir ataques de reentrada, cruciales durante las interacciones con Uniswap.

Optimización de Gas:

Uso unchecked: Las restas de balance en withdrawUsdc son 100% seguras gracias al modificador validWithdrawalAmount.

Se cachea totalBalanceUsdc en memoria (_totalBalanceUsdc).

### 🚀 Despliegue en Foundry

#### Script de Despliegue
El script de despliegue se encuentra en `script/DeployKipuBankV3.s.sol`.
#### Parámetros de Despliegue
- _ethOracle: Dirección del oráculo ETH/USD de Chainlink.
- _router: Dirección del Router de Uniswap V2.
- _usdc: Dirección del token USDC.
- _withdrawalLimit: Límite de retiro en USDC (con 6 decimales).
- _bankCap: Límite total del banco en USDC (con 6 decimales).
- initialOwner: Dirección de wallet que recibirá el ADMIN_ROLE.

#### Ejecución del Script
```bash
forge script script/DeployKipuBankV3.s.sol:DeployKipuBankV3 --rpc-url <RPC_URL> --account <ACCOUNT> --sender <SENDER_ADDRESS> --broadcast  --verify --etherscan-api-key <ETHERSCAN_API_KEY>
``` 

### 🕹️ Interacción

#### 💰 **Depósitos**

#### `depositEth(amountOutMin)`
Permite depositar **ETH nativo**, que se intercambia automáticamente a **USDC** y se acredita al balance del usuario.  

**Argumentos:**
- `amountOutMin` *(uint256)* → Protección contra *slippage*: monto mínimo de USDC a recibir.

---

#### `depositToken(token, amount, amountOutMin)`
Permite depositar **tokens ERC20** (previamente aprobados), que se swappean a **USDC**.  

**Argumentos:**
- `token` *(address)* → Dirección del token que se desea depositar.  
- `amount` *(uint256)* → Cantidad del token a depositar.  
- `amountOutMin` *(uint256)* → Monto mínimo de USDC a recibir.

---

#### 💸 **Retiros**

#### `withdrawUsdc(amount)`
Retira **USDC** del balance del usuario hacia su wallet, respetando el límite establecido por `WITHDRAWAL_LIMIT`.

**Argumentos:**
- `amount` *(uint256)* → Cantidad de USDC a retirar.

---

#### 🔍 **Consultas**

#### `getUserBalance(account)`
Devuelve el **saldo actual en USDC** del usuario especificado.  

**Argumentos:**
- `account` *(address)* → Dirección del usuario a consultar.

---

#### `previewDeposit(tokenIn, amountIn)`
Devuelve una **estimación** de cuántos **USDC** se recibirían al depositar una cantidad específica de un token.  

**Argumentos:**
- `tokenIn` *(address)* → Token de entrada.  
- `amountIn` *(uint256)* → Cantidad a depositar.

---

#### 🔧 **Administración**

#### `pause()` / `unpause()`
(Solo **Admin**) Pausa o reactiva **todas las operaciones** de depósito y retiro.

---

#### `setFeeds(token, feed)`
(Solo **Admin**) Asocia un **oráculo de Chainlink** para obtener precios en tiempo real de un token.  

**Argumentos:**
- `token` *(address)* → Dirección del token.  
- `feed` *(address)* → Dirección del contrato del oráculo de precios.

---

#### `getEthPrice()` / `getTokenPrice(token)`
Funciones de **consulta de precios** mediante los oráculos de Chainlink.  

**Argumentos (solo para `getTokenPrice`):**
- `token` *(address)* → Dirección del token del que se desea conocer el precio.
---

### ⚖️ Notas de Diseño

🔒 Control de Acceso en el Constructor
El Diseño: El constructor asigna el ADMIN_ROLE al initialOwner y también establece que el ADMIN_ROLE es el administrador de sí mismo (_setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE)).

Esto permite al initialOwner (o a cualquier cuenta a la que le dé ADMIN_ROLE) nombrar a otros administradores usando la función grantRole(ADMIN_ROLE, <nueva_direccion>).

En futuras actualizaciones, se podría implementar un control de acceso más granular, permitiendo diferentes roles para diferentes funciones administrativas.

### 📄 Contrato verificado en Sepolia

https://sepolia.etherscan.io/address/0xf7001fa212447658d062fd3b3e8faa4fb7a86ec1#code

### Cobertura de pruebas


#### Métodos de prueba implementados:

Se utilizó vm.createSelectFork para "forkear" (copiar) el estado de zetachain en un entorno de prueba local. Esto permitió interactuar con contratos reales desplegados.

Se usó vm.prank para simular transacciones desde direcciones específicas, como USER y WHALE (para obtener fondos de prueba).

Se utilizó vm.deal para "fabricar" ETH nativo y asignarlo al USER para la prueba de depositEth.

Los siguientes métodos de prueba fueron implementados en test/KipuBankV3.t.sol:
- testDepositUsdcToken
- testDepositERC20Token
- testDepositEth
- testBankCapExceededMustRevert
- testWithdraw
- testGetUserBalance
- testPreviewDeposit
- testPauseUnpause
