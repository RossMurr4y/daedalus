# daedalus

This repository contains the necessary parts to build and deploy a Cardano staking node on the jormungandr test network.
#
## Image Build

### Description
The image build process occurs in two stages. The first is the "builder" stage, that makes use of the ekidd/rust-musl-builder docker image to compile the jormungandr binaries using static linking. This will ensure the binaries are self-contained.

The second stage is the "node" stage which uses a clean Alpine container image. A user account is setup on the base image ("cardano") and the self-contained binaries are copied over from the builder stage.

### Prerequisites
- [docker](https://docs.docker.com/install/)
- [yq](https://mikefarah.github.io/yq/) (for stake pool setup only)

### Commands
```
cd <Dockerfile dir>
docker build .
```
#
## Run Container Image

### Description
The following commands can be used to trigger any of the commands above through docker. By doing so you should be able to perform all actions necessary to configgure and run a node on the cardano network.

[Jormungandr User Guide](https://input-output-hk.github.io/jormungandr/introduction.html)

### List of Commands
- [jormungandr](https://input-output-hk.github.io/jormungandr/introduction.html)
- [jcli](https://input-output-hk.github.io/jormungandr/jcli/introduction.html)

See their corresponding documentation for sub-commands, or use the ```--help``` argument on the container (see below).

### Usage

#### Retrieve image name
```
docker image list
```

#### Run "jormungandr" (default usage)
```
docker run <image-name>

# Example - run the default image.
docker run rossmurr4y/daedalus

# Using version tags
docker run rossmurr4y/daedalus:latest
```

#### Run "jcli"
```
# docker run --entrypoint jcli <image-name> [<jcli-arguments>]

# Example: run "jcli utils --help"
docker run --entrypoint jcli rossmurr4y/daedalus utils --help
```
#
# Stake Pool Setup

## Assumptions:

It is assumed that when following the below instructions to setup a stake pool that you are running a Linux OS using bash. Other OS's should work but you will need to make your own adjustments.

It is assumed that you have created a workind directory for yourself such as ```~/daedalus``` and unless specified otherwise these commands are run from there.

## Local Alias

fast local access to jcli can be enabled through use of an alias, stored in your ~/.bashrc file. We'll mount our home drive to the cardano home drive to store output files.

```
echo "alias jcli='docker run --entrypoint jcli -v ~/daedalus:/home/cardano rossmurr4y/daedalus'" >> ~/.bashrc
source ~/.bashrc
```

## KeyPairs

Performed locally, we will generate the files necessary for successful setup of a staking node. Once created, you will want to store these somewhere easily accessible to a running container.

- encryption keys (VRF for leader election participation & KES for signing blocks with stake key for identifying yourself as owner)
- node configuration file

### Generate VRF Keypair
```
# generate private key to your local machine (to the volume mount in above alias)
jcli key generate --type=Curve25519_2HashDH > stake_pool_vrf.prv

# generate public key from the private key
jcli key to-public --input /home/cardano/stake_pool_vrf.prv > stake_pool_vrf.pub

# verify both files now exist locally
ls

# and both have unique content
cat *
```

### Generate KES Keypair
Same as previous keypair, but with different encryption type and file names.
```
jcli key generate --type=SumEd25519_12 > stake_pool_kes.prv
jcli key to-public --input /home/cardano/stake_pool_kes.prv > stake_pool_kes.pub

# stake_pool_kes.prv will be quite long,  the others 1-liners.
ls
cat *
```

### Generate Owner Key
```
 jcli key generate --type=Ed25519Extended > owner_key.prv
 jcli key to-public --input /home/cardano/owner_key.prv > owner_key.pub
```

[More Information](https://input-output-hk.github.io/jormungandr/stake_pool/registering_stake_pool.html)

## Create a Stake Pool Certificate & Retreive Stake Pool Id

In order to participate on an existing blockchain, a certificate must be generated using the newly minted keypairs. From this certificate we will retrieve the Stake Pool Id that uniquely identifies our node.

### Generate Certificate
```
jcli certificate new stake-pool-registration \
    --kes-key $(cat stake_pool_kes.pub) \
    --vrf-key $(cat stake_pool_vrf.pub) \
    --start-validity 0 \
    --management-threshold 1 \
    --tax-fixed 1000000 \
    --tax-limit 1000000000 \
    --tax-ratio "1/10" \
    --owner $(cat owner_key.pub) > stake_pool.cert
```

### Retreive Stake Pool Id
```
jcli certificate get-stake-pool-id /home/cardano/stake_pool.cert > stake_pool.id
```

### Create Secrets YAML File
All the "secrets" (private keys) are going to need to be passed to jormungandr when we start the node. We do this by creating a secrets yaml file, and pass that instead of them all one at a time.

**Note**: YAML is very reliant on syntax. To ensure consistency the steps below will build the configuration file using the application "yq".

```
# create the secrets file
echo "---" > node_secret.yaml

# add the kes (signing), vrf and node id secrets
yq write -i node_secret.yaml genesis.sig_key $(cat stake_pool_kes.prv)
yq write -i node_secret.yaml genesis.vrf_key $(cat stake_pool_vrf.prv)
yq write -i node_secret.yaml genesis.node_id $(cat stake_pool.id)
```

## Node Configuration File
A YAML document is required to tell the node the various configuration settings to use when it starts up. In these steps we'll create a standard YAML document that the average node operator would use. More advanced configuration can be achieved by exploring the other settings in the [jormungandr user guide](https://input-output-hk.github.io/jormungandr/configuration/introduction.html).

```
# start by creating an empty yaml file.
echo "---" > jormungandr_config.yaml

# set storage location for the blockchain. Skip to keep in-memory.
yq write -i jormungandr_config.yaml storage /temp/storage

# set the logging information. entirely optional but useful.
yq write -i jormungandr_config.yaml log.level warn
yq write -i jormungandr_config.yaml log.format json
yq write -i jormungandr_config.yaml log.output.file /temp/storage/jormungandr.log

# set p2p configuration. Replace with your Public IP Address
yq write -i jormungandr_config.yaml p2p.public_address /ip4/<public-ip-address>/tcp/8080
yq write -i jormungandr_config.yaml p2p.topics_of_interest.messages high
yq write -i jormungandr_config.yaml p2p.topics_of_interest.blocks high

```

## Genisis Hash YAML File
We're going to create a yaml file for storing and retrieving the genisis block hash values for any blockchains that we want to connect to. For some this may only be a single blockchain however if you are running across multiple networks (not just test) then its handy to have them all in one place in a simple format.

[Official Genesis Block Hashes](https://hydra.iohk.io/build/1523436/download/1/index.html)
```
# create your file
echo "---" > genesis_blocks.yaml

# repeat the following for as many hashes as you wish to store.
# Example: yd write -i genesis_blocks.yaml <cluster> <hash>
yq write -i genesis_blocks.yaml itn_rewards_v1 	8e4d2a343f3dcf9330ad9035b3e8d168e6728904262f2c434a4f8f934ec7b676
```

## Starting Your Node
Now we have our node configuration file and genesis hash file, we can start our node!
```
hash=$(yq read genesis_blocks.yaml itn_rewards_v1)
docker run rossmurr4y/jormungandr --genesis-block-hash $hash --config /home/cardano/jormungandr_config.yaml
```
If all was successful, you should see the node begin to connect to the jormungandr network and begin syncing the node. If you did not provide a storage location in your node configuration yaml then it will store the blockchain in memory and be lost when the container is destroyed.