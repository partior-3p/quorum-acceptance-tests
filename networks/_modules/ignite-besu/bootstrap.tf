locals {
  enode_urls = formatlist("\"enode://%s@%s:%d\"", quorum_bootstrap_node_key.nodekeys-generator[*].hex_node_id, var.besu_networking[*].ip.private, var.besu_networking[*].port.p2p)

  # metadata for network subjected to initial participants input
  network = {
    hexNodeIds = [for idx in local.node_indices : quorum_bootstrap_node_key.nodekeys-generator[idx].hex_node_id if lookup(local.node_initial_paticipants, idx, "false") == "true"]
    networking = [for idx in local.node_indices : var.besu_networking[idx] if lookup(local.node_initial_paticipants, idx, "false") == "true"]
    enode_urls = [for idx in local.node_indices : local.enode_urls[idx] if lookup(local.node_initial_paticipants, idx, "false") == "true"]
  }

  besu_dirs      = [for idx in local.node_indices : format("%s/%s%s", quorum_bootstrap_network.this.network_dir_abs, local.node_dir_prefix, idx)]
  ethsigner_dirs = [for idx in local.node_indices : format("%s/%s%s", quorum_bootstrap_network.this.network_dir_abs, local.ethsigner_dir_prefix, idx)]

  chainId    = local.hybrid_network ? var.hybrid_network_id : random_integer.network_id.result
}

data "null_data_source" "meta" {
  count = local.number_of_nodes
  inputs = {
    idx             = count.index
    tmKeys          = join(",", [for k in local.tm_named_keys_alloc[count.index] : element(local.key_data, index(local.tm_named_keys_all, k))])
    nodeUrl         = format("http://%s:%d", var.ethsigner_networking[count.index].ip.public, var.ethsigner_networking[count.index].port.external)
    tmThirdpartyUrl = format("http://%s:%d", var.tm_networking[count.index].ip.public, var.tm_networking[count.index].port.thirdparty.external)
    graphqlUrl      = format("http://%s:%d/graphql", var.besu_networking[count.index].ip.public, var.besu_networking[count.index].port.graphql.external)
  }
}

resource "random_integer" "network_id" {
  max = 3000
  min = 1400
}

resource "quorum_bootstrap_network" "this" {
  name       = local.network_name
  target_dir = local.generated_dir
}

resource "quorum_bootstrap_keystore" "accountkeys-generator" {
  count                = local.hybrid_network ? 0 : local.number_of_nodes
  keystore_dir         = format("%s/%s", local.ethsigner_dirs[count.index], local.keystore_folder)
  use_light_weight_kdf = true

  dynamic "account" {
    for_each = lookup(local.named_accounts_alloc, count.index)
    content {
      passphrase = local.keystore_password
      balance    = "1000000000000000000000000000"
    }
  }
}

resource "local_file" "keystore_password" {
  count    = local.number_of_nodes
  filename = format("%s/%s", local.ethsigner_dirs[count.index], local.keystore_password_file)
  content  = local.keystore_password
}

resource "quorum_bootstrap_node_key" "nodekeys-generator" {
  count = local.number_of_nodes
}

resource "quorum_transaction_manager_keypair" "tm" {
  count = length(local.tm_named_keys_all)
  config {
    memory = 100000
  }
}

resource "local_file" "tm" {
  count    = length(local.tm_named_keys_all)
  filename = format("%s/%s", local.tmkeys_generated_dir, element(local.tm_named_keys_all, count.index))
  content  = local.key_data[count.index]
}

resource "local_file" "tm_publickey" {
  count    = length(local.tm_named_keys_all)
  filename = format("%s/tmkey.pub", local.besu_dirs[count.index])
  content  = local.public_key_b64[count.index]
}

data "quorum_bootstrap_genesis_mixhash" "this" {

}

resource "quorum_bootstrap_istanbul_extradata" "this" {
  istanbul_addresses = [for idx in local.node_indices : quorum_bootstrap_node_key.nodekeys-generator[idx].istanbul_address if lookup(local.istanbul_validators, idx, "false") == "true"]
  mode               = "ibft2"
}

resource "local_file" "genesis-file" {
  filename = format("%s/genesis.json", quorum_bootstrap_network.this.network_dir_abs)
  content  = <<-EOF
{
  "coinbase": "0x0000000000000000000000000000000000000000",
  "config" : {
    "chainId" : ${local.chainId},
      "homesteadBlock": 0,
      "byzantiumBlock": 0,
      "constantinopleBlock":0,
      "istanbulBlock":0,
      "petersburgBlock":0,
      "eip150Block": 0,
      "eip155Block": 0,
      "eip150Hash": "0x0000000000000000000000000000000000000000000000000000000000000000",
      "eip158Block": 0,
%{if var.consensus == "ibft2"~}
    "ibft2" : {
      "blockperiodseconds" : 1,
      "epochlength" : 30000,
      "requesttimeoutseconds" : 10
    },
%{endif~}
%{if var.consensus == "qbft"~}
    "qbft" : {
      "blockperiodseconds" : 1,
      "epochlength" : 30000,
      "requesttimeoutseconds" : 10
    },
%{endif~}
    "isQuorum": true
  },
  "difficulty" : "0x1",
%{if var.hybrid_network~}
  "extraData": "${var.hybrid_extradata}",
%{else~}
  "extraData": "${quorum_bootstrap_istanbul_extradata.this.extradata}",
%{endif~}
  "gasLimit" : "0xFFFFFF00",
  "mixhash": "${data.quorum_bootstrap_genesis_mixhash.this.istanbul}",
  "nonce" : "0x0",
  "parentHash": "0x0000000000000000000000000000000000000000000000000000000000000000",
  "timestamp": "0x00",
%{if local.hybrid_network~}
  "alloc": {
    ${join(",", var.hybrid_account_alloc)}
  }
%{else~}
  "alloc": {
      ${join(",", formatlist("\"%s\" : { \"balance\": \"%s\" }", quorum_bootstrap_keystore.accountkeys-generator[*].account[0].address, quorum_bootstrap_keystore.accountkeys-generator[*].account[0].balance))},
      "0x0000000000000000000000000000000000008888": {
        "comment": "Account Ingress smart contract",
        "balance": "0",
        "code": "0x608060405234801561001057600080fd5b506004361061009e5760003560e01c8063936421d511610066578063936421d5146101ca578063a43e04d8146102fb578063de8fa43114610341578063e001f8411461035f578063fe9fbb80146103c55761009e565b80630d2020dd146100a357806310d9042e1461011157806311601306146101705780631e7c27cb1461018e5780638aa10435146101ac575b600080fd5b6100cf600480360360208110156100b957600080fd5b8101908080359060200190929190505050610421565b604051808273ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200191505060405180910390f35b6101196104d6565b6040518080602001828103825283818151815260200191508051906020019060200280838360005b8381101561015c578082015181840152602081019050610141565b505050509050019250505060405180910390f35b61017861052e565b6040518082815260200191505060405180910390f35b610196610534565b6040518082815260200191505060405180910390f35b6101b461053a565b6040518082815260200191505060405180910390f35b6102e1600480360360c08110156101e057600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff169060200190929190803573ffffffffffffffffffffffffffffffffffffffff1690602001909291908035906020019092919080359060200190929190803590602001909291908035906020019064010000000081111561025b57600080fd5b82018360208201111561026d57600080fd5b8035906020019184600183028401116401000000008311171561028f57600080fd5b91908080601f016020809104026020016040519081016040528093929190818152602001838380828437600081840152601f19601f820116905080830192505050505050509192919290505050610544565b604051808215151515815260200191505060405180910390f35b6103276004803603602081101561031157600080fd5b810190808035906020019092919050505061073f565b604051808215151515815260200191505060405180910390f35b610349610a1e565b6040518082815260200191505060405180910390f35b6103ab6004803603604081101561037557600080fd5b8101908080359060200190929190803573ffffffffffffffffffffffffffffffffffffffff169060200190929190505050610a2b565b604051808215151515815260200191505060405180910390f35b610407600480360360208110156103db57600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff169060200190929190505050610caf565b604051808215151515815260200191505060405180910390f35b60008060001b821161049b576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260208152602001807f436f6e7472616374206e616d65206d757374206e6f7420626520656d7074792e81525060200191505060405180910390fd5b6002600083815260200190815260200160002060009054906101000a900473ffffffffffffffffffffffffffffffffffffffff169050919050565b6060600380548060200260200160405190810160405280929190818152602001828054801561052457602002820191906000526020600020905b815481526020019060010190808311610510575b5050505050905090565b60005481565b60015481565b6000600554905090565b60008073ffffffffffffffffffffffffffffffffffffffff16610568600054610421565b73ffffffffffffffffffffffffffffffffffffffff16141561058d5760019050610735565b600260008054815260200190815260200160002060009054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1663936421d58888888888886040518763ffffffff1660e01b8152600401808773ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1681526020018673ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200185815260200184815260200183815260200180602001828103825283818151815260200191508051906020019080838360005b838110156106a857808201518184015260208101905061068d565b50505050905090810190601f1680156106d55780820380516001836020036101000a031916815260200191505b5097505050505050505060206040518083038186803b1580156106f757600080fd5b505afa15801561070b573d6000803e3d6000fd5b505050506040513d602081101561072157600080fd5b810190808051906020019092919050505090505b9695505050505050565b60008060001b82116107b9576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260208152602001807f436f6e7472616374206e616d65206d757374206e6f7420626520656d7074792e81525060200191505060405180910390fd5b600060038054905011610817576040517f08c379a0000000000000000000000000000000000000000000000000000000008152600401808060200182810382526047815260200180610e446047913960600191505060405180910390fd5b61082033610caf565b610875576040517f08c379a000000000000000000000000000000000000000000000000000000000815260040180806020018281038252602b815260200180610e19602b913960400191505060405180910390fd5b6000600460008481526020019081526020016000205490506000811180156108a257506003805490508111155b15610a135760038054905081146109105760006003600160038054905003815481106108ca57fe5b9060005260206000200154905080600360018403815481106108e857fe5b9060005260206000200181905550816004600083815260200190815260200160002081905550505b600380548061091b57fe5b600190038181906000526020600020016000905590556000600460008581526020019081526020016000208190555060006002600085815260200190815260200160002060006101000a81548173ffffffffffffffffffffffffffffffffffffffff021916908373ffffffffffffffffffffffffffffffffffffffff1602179055507fe3d908a1f6d2467f8e7c8198f30125843211345eedb763beb4cdfb7fe728a5af600084604051808373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1681526020018281526020019250505060405180910390a16001915050610a19565b60009150505b919050565b6000600380549050905090565b60008060001b8311610aa5576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260208152602001807f436f6e7472616374206e616d65206d757374206e6f7420626520656d7074792e81525060200191505060405180910390fd5b600073ffffffffffffffffffffffffffffffffffffffff168273ffffffffffffffffffffffffffffffffffffffff161415610b2b576040517f08c379a0000000000000000000000000000000000000000000000000000000008152600401808060200182810382526022815260200180610e8b6022913960400191505060405180910390fd5b610b3433610caf565b610b89576040517f08c379a000000000000000000000000000000000000000000000000000000000815260040180806020018281038252602b815260200180610e19602b913960400191505060405180910390fd5b600060046000858152602001908152602001600020541415610be8576003839080600181540180825580915050906001820390600052602060002001600090919290919091505560046000858152602001908152602001600020819055505b816002600085815260200190815260200160002060006101000a81548173ffffffffffffffffffffffffffffffffffffffff021916908373ffffffffffffffffffffffffffffffffffffffff1602179055507fe3d908a1f6d2467f8e7c8198f30125843211345eedb763beb4cdfb7fe728a5af8284604051808373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1681526020018281526020019250505060405180910390a16001905092915050565b60008073ffffffffffffffffffffffffffffffffffffffff1660026000600154815260200190815260200160002060009054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff161415610d235760019050610e13565b60026000600154815260200190815260200160002060009054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1663fe9fbb80836040518263ffffffff1660e01b8152600401808273ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200191505060206040518083038186803b158015610dd557600080fd5b505afa158015610de9573d6000803e3d6000fd5b505050506040513d6020811015610dff57600080fd5b810190808051906020019092919050505090505b91905056fe4e6f7420617574686f72697a656420746f2075706461746520636f6e74726163742072656769737472792e4d7573742068617665206174206c65617374206f6e65207265676973746572656420636f6e747261637420746f20657865637574652064656c657465206f7065726174696f6e2e436f6e74726163742061646472657373206d757374206e6f74206265207a65726f2ea265627a7a7230582041609b4b53a670d9d29d1c024dd9467b05a85c59786466daf08dcc1f75f8f6be64736f6c63430005090032",
        "storage": {
          "0x0000000000000000000000000000000000000000000000000000000000000000": "0x72756c6573000000000000000000000000000000000000000000000000000000",
          "0x0000000000000000000000000000000000000000000000000000000000000001": "0x61646d696e697374726174696f6e000000000000000000000000000000000000",
          "0x0000000000000000000000000000000000000000000000000000000000000004": "0x0f4240"
        }
      },
      "0x0000000000000000000000000000000000009999": {
        "comment": "Node Ingress smart contract",
        "balance": "0",
        "code": "0x608060405234801561001057600080fd5b50600436106100885760003560e01c8063a43e04d81161005b578063a43e04d814610196578063de8fa431146101dc578063e001f841146101fa578063fe9fbb801461026057610088565b80630d2020dd1461008d57806310d9042e146100fb578063116013061461015a5780631e7c27cb14610178575b600080fd5b6100b9600480360360208110156100a357600080fd5b81019080803590602001909291905050506102bc565b604051808273ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200191505060405180910390f35b610103610371565b6040518080602001828103825283818151815260200191508051906020019060200280838360005b8381101561014657808201518184015260208101905061012b565b505050509050019250505060405180910390f35b6101626103c9565b6040518082815260200191505060405180910390f35b6101806103cf565b6040518082815260200191505060405180910390f35b6101c2600480360360208110156101ac57600080fd5b81019080803590602001909291905050506103d5565b604051808215151515815260200191505060405180910390f35b6101e46106b4565b6040518082815260200191505060405180910390f35b6102466004803603604081101561021057600080fd5b8101908080359060200190929190803573ffffffffffffffffffffffffffffffffffffffff1690602001909291905050506106c1565b604051808215151515815260200191505060405180910390f35b6102a26004803603602081101561027657600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff169060200190929190505050610945565b604051808215151515815260200191505060405180910390f35b60008060001b8211610336576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260208152602001807f436f6e7472616374206e616d65206d757374206e6f7420626520656d7074792e81525060200191505060405180910390fd5b6002600083815260200190815260200160002060009054906101000a900473ffffffffffffffffffffffffffffffffffffffff169050919050565b606060038054806020026020016040519081016040528092919081815260200182805480156103bf57602002820191906000526020600020905b8154815260200190600101908083116103ab575b5050505050905090565b60005481565b60015481565b60008060001b821161044f576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260208152602001807f436f6e7472616374206e616d65206d757374206e6f7420626520656d7074792e81525060200191505060405180910390fd5b6000600380549050116104ad576040517f08c379a0000000000000000000000000000000000000000000000000000000008152600401808060200182810382526047815260200180610ada6047913960600191505060405180910390fd5b6104b633610945565b61050b576040517f08c379a000000000000000000000000000000000000000000000000000000000815260040180806020018281038252602b815260200180610aaf602b913960400191505060405180910390fd5b60006004600084815260200190815260200160002054905060008111801561053857506003805490508111155b156106a95760038054905081146105a657600060036001600380549050038154811061056057fe5b90600052602060002001549050806003600184038154811061057e57fe5b9060005260206000200181905550816004600083815260200190815260200160002081905550505b60038054806105b157fe5b600190038181906000526020600020016000905590556000600460008581526020019081526020016000208190555060006002600085815260200190815260200160002060006101000a81548173ffffffffffffffffffffffffffffffffffffffff021916908373ffffffffffffffffffffffffffffffffffffffff1602179055507fe3d908a1f6d2467f8e7c8198f30125843211345eedb763beb4cdfb7fe728a5af600084604051808373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1681526020018281526020019250505060405180910390a160019150506106af565b60009150505b919050565b6000600380549050905090565b60008060001b831161073b576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260208152602001807f436f6e7472616374206e616d65206d757374206e6f7420626520656d7074792e81525060200191505060405180910390fd5b600073ffffffffffffffffffffffffffffffffffffffff168273ffffffffffffffffffffffffffffffffffffffff1614156107c1576040517f08c379a0000000000000000000000000000000000000000000000000000000008152600401808060200182810382526022815260200180610b216022913960400191505060405180910390fd5b6107ca33610945565b61081f576040517f08c379a000000000000000000000000000000000000000000000000000000000815260040180806020018281038252602b815260200180610aaf602b913960400191505060405180910390fd5b60006004600085815260200190815260200160002054141561087e576003839080600181540180825580915050906001820390600052602060002001600090919290919091505560046000858152602001908152602001600020819055505b816002600085815260200190815260200160002060006101000a81548173ffffffffffffffffffffffffffffffffffffffff021916908373ffffffffffffffffffffffffffffffffffffffff1602179055507fe3d908a1f6d2467f8e7c8198f30125843211345eedb763beb4cdfb7fe728a5af8284604051808373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1681526020018281526020019250505060405180910390a16001905092915050565b60008073ffffffffffffffffffffffffffffffffffffffff1660026000600154815260200190815260200160002060009054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1614156109b95760019050610aa9565b60026000600154815260200190815260200160002060009054906101000a900473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1663fe9fbb80836040518263ffffffff1660e01b8152600401808273ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200191505060206040518083038186803b158015610a6b57600080fd5b505afa158015610a7f573d6000803e3d6000fd5b505050506040513d6020811015610a9557600080fd5b810190808051906020019092919050505090505b91905056fe4e6f7420617574686f72697a656420746f2075706461746520636f6e74726163742072656769737472792e4d7573742068617665206174206c65617374206f6e65207265676973746572656420636f6e747261637420746f20657865637574652064656c657465206f7065726174696f6e2e436f6e74726163742061646472657373206d757374206e6f74206265207a65726f2ea265627a7a723058206703bdfb54a7a3eb61936f024bb43f91b3a8ce1448dc4d9593458137e30b983f64736f6c63430005090032",
        "storage": {
          "0x0000000000000000000000000000000000000000000000000000000000000000": "0x72756c6573000000000000000000000000000000000000000000000000000000",
          "0x0000000000000000000000000000000000000000000000000000000000000001": "0x61646d696e697374726174696f6e000000000000000000000000000000000000",
          "0x0000000000000000000000000000000000000000000000000000000000000004": "0x0f4240"
        }
      }
    }
%{endif~}
}
EOF
}

resource "local_file" "node-key" {
  count    = local.number_of_nodes
  filename = format("%s/key", local.besu_dirs[count.index])
  content  = local.hybrid_network ? var.hybrid_node_key[count.index] : quorum_bootstrap_node_key.nodekeys-generator[count.index].node_key_hex
}

resource "local_file" "static-nodes" {
  count    = local.number_of_nodes
  filename = format("%s/static-nodes.json", local.besu_dirs[count.index])
  content  = local.hybrid_network == true ? "[${join(",", var.hybrid_enodeurls)}]" : "[${join(",", local.network.enode_urls)}]"
}

resource "local_file" "permissioned-nodes" {
  count    = local.number_of_nodes
  filename = format("%s/permissioned-nodes.json", local.besu_dirs[count.index])
  content  = local_file.static-nodes[count.index].content
}

resource "local_file" "genesisfile" {
  count    = local.number_of_nodes
  filename = format("%s/%s", local.besu_dirs[count.index], local.genesis_file)
  content  = local_file.genesis-file.content
}

resource "local_file" "besuconfigfile" {
  count    = local.number_of_nodes
  filename = format("%s/config.toml", local.besu_dirs[count.index])
  content  = <<-EOF
logging="DEBUG"
data-path="/opt/besu/data"
host-whitelist=["*"]

# rpc
rpc-http-enabled=true
rpc-http-host="0.0.0.0"
rpc-http-port=${var.besu_networking[count.index].port.http.internal}
rpc-http-cors-origins=["*"]

# ws
rpc-ws-enabled=true
rpc-ws-host="0.0.0.0"
rpc-ws-port=${var.besu_networking[count.index].port.ws.internal}

# graphql
graphql-http-enabled=true
graphql-http-host="0.0.0.0"
graphql-http-port=${var.besu_networking[count.index].port.graphql.internal}
graphql-http-cors-origins=["*"]

# metrics
metrics-enabled=false

# bootnodes
discovery-enabled=false

EOF
}

resource "local_file" "tmconfigs-generator" {
  count    = local.number_of_nodes
  filename = format("%s/%s%s/config.json", quorum_bootstrap_network.this.network_dir_abs, local.tm_dir_prefix, local.total_node_indices[count.index])
  content  = <<-JSON
{
    "useWhiteList": false,
    "jdbc": {
        "username": "sa",
        "password": "",
        "url": "[TO BE OVERRIDREN FROM COMMAND LINE]",
        "autoCreateTables": true
    },
    "serverConfigs":[
        {
            "app":"ThirdParty",
            "enabled": true,
            "serverAddress": "http://${var.tm_networking[local.total_node_indices[count.index]].ip.private}:${var.tm_networking[local.total_node_indices[count.index]].port.thirdparty.internal}",
            "communicationType" : "REST"
        },
        {
            "app":"Q2T",
            "enabled": true,
            "serverAddress":"[TO BE OVERRIDDEN FROM COMMAND LINE]",
            "communicationType" : "REST"
        },
        {
            "app":"P2P",
            "enabled": true,
            "serverAddress":"http://${var.tm_networking[local.total_node_indices[count.index]].ip.private}:${var.tm_networking[local.total_node_indices[count.index]].port.p2p}",
            "sslConfig": {
              "tls": "OFF",
              "generateKeyStoreIfNotExisted": true,
              "serverKeyStore": "[TO BE OVERRIDREN FROM COMMAND LINE]",
              "serverKeyStorePassword": "quorum",
              "serverTrustStore": "[TO BE OVERRIDREN FROM COMMAND LINE]",
              "serverTrustStorePassword": "quorum",
              "serverTrustMode": "TOFU",
              "knownClientsFile": "[TO BE OVERRIDREN FROM COMMAND LINE]",
              "clientKeyStore": "[TO BE OVERRIDREN FROM COMMAND LINE]",
              "clientKeyStorePassword": "quorum",
              "clientTrustStore": "[TO BE OVERRIDREN FROM COMMAND LINE]",
              "clientTrustStorePassword": "quorum",
              "clientTrustMode": "TOFU",
              "knownServersFile": "[TO BE OVERRIDREN FROM COMMAND LINE]"
            },
            "communicationType" : "REST"
        }
    ],
    "peer": [${join(",", formatlist("{\"url\" : \"http://%s:%d\"}", var.tm_networking[*].ip.private, var.tm_networking[*].port.p2p))}],
    "keys": {
      "passwords": [],
      "keyData": [${local.hybrid_network ? var.hybrid_tmkeys[local.number_of_quorum_nodes + count.index] : data.null_data_source.meta[count.index].inputs.tmKeys}]
    },
    "alwaysSendTo": [],
    "features" : {
      "enableRemoteKeyValidation" : "true"
    }
}
JSON
}