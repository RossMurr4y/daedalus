#!/bin/bash

# Build the latest "jormungandr" test network from source.

mkdir -p ./bin

# Clone cardano network from source
git clone --recurse-submodules "https://github.com/input-output-hk/jormungandr.git"
cd jormungandr

# Retrieve the latest tag from the source repo & checkout
# (cant just use latest tag, as some tags may be staged but not latest release.)
latest_version=$(curl --silent "https://api.github.com/repos/input-output-hk/jormungandr/releases/latest" | jq -r .tag_name)
git checkout tags/${latest_version}

# Build cardano network & jcli from source + output to our staging bin directory.
cargo install --path jormungandr --features systemd --root /home/cardano/daedalus/bin
cargo install --path jcli --root /home/cardano/daedalus/bin