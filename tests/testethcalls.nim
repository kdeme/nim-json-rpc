import unittest, json, tables
import ../rpcclient, ../rpcsockets
import stint, ethtypes, ethprocs, stintjson, nimcrypto, ethhexstrings, chronicles

from os import getCurrentDir, DirSep
from strutils import rsplit
template sourceDir: string = currentSourcePath.rsplit(DirSep, 1)[0]

var
  server = newRpcSocketServer("localhost", Port(8546))
  client = newRpcStreamClient()

## Generate Ethereum server RPCs
server.addEthRpcs()

## Generate client convenience marshalling wrappers from forward declarations
createRpcSigs(sourceDir & DirSep & "ethcallsigs.nim")

## Create custom RPC with StUint input parameter
server.rpc("rpc.uint256param") do(i: UInt256):
  let r = i + 1.stUint(256)
  result = %r

## Create custom RPC with StUInt return parameter
server.rpc("rpc.testreturnuint256") do() -> UInt256:
  let r: UInt256 = "0x1234567890abcdef".parse(UInt256, 16)
  return r

proc testLocalCalls: Future[seq[JsonNode]] =
  ## Call RPCs created with `rpc` locally.
  ## This simply demonstrates async calls of the procs generated by the `rpc` macro.
  var
    uint256Param =  rpcUInt256Param(%[%"0x1234567890"])
    returnUint256 = rpcTestReturnUInt256(%[])
  result = all(uint256Param, returnUint256)

proc testRemoteUInt256: Future[seq[Response]] =
  ## Call function remotely on server, testing `stint` types
  var
    uint256Param =  client.call("rpc.uint256param", %[%"0x1234567890"])
    returnUint256 = client.call("rpc.testreturnuint256", %[])
  result = all(uint256Param, returnUint256)

proc testSigCalls: Future[seq[string]] =
  ## Remote call using proc generated from signatures in `ethcallsigs.nim`
  var
    version = client.web3_clientVersion()
    sha3 = client.web3_sha3("0x68656c6c6f20776f726c64")
  result = all(version, sha3)

server.start()
waitFor client.connect("localhost", Port(8546))


suite "Local calls":
  let localResults = testLocalCalls().waitFor
  test "UInt256 param local":
    check localResults[0] == %"0x1234567891"
  test "Return UInt256 local":
    check localResults[1] == %"0x1234567890abcdef"

suite "Remote calls":
  let remoteResults = testRemoteUInt256().waitFor
  test "UInt256 param":
    check remoteResults[0].result == %"0x1234567891"
  test "Return UInt256":
    check remoteResults[1].result == %"0x1234567890abcdef"

suite "Generated from signatures":
  let sigResults = testSigCalls().waitFor
  test "Version":
    check sigResults[0] == "Nimbus-RPC-Test"
  test "SHA3":
    check sigResults[1] == "0x47173285A8D7341E5E972FC677286384F802F8EF42A5EC5F03BBFA254CB01FAD"

server.stop()
server.close()
