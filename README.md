terraform init

terraform plan

terraform apply

docker ps -f name=lvm --format "table {{.Names}}\t{{.Status}}"

export VAULT_ADDR=http://127.0.0.1:8200

``` sh
vault operator init \
    -key-shares=1 \
    -key-threshold=1 \
    | head -n3 \
    | cat > .vault-init
```
    
vault operator unseal $(grep 'Unseal Key 1'  .vault-init | awk '{print $NF}')

vault login -no-print \
$(grep 'Initial Root Token' .vault-init | awk '{print $NF}')

vault token lookup | grep policies

vault audit enable file file_path=/vault/logs/vault-audit.log
