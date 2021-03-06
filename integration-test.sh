#!/usr/bin/env bash

echo "Testing Alice..."
curl --request POST \
  --url http://localhost:8080/rpc \
  --header 'content-type: application/json' \
  --data '{
	"id": 1,
	"method": "FundingService.Approve",
	"params": [{
		"amount": "0x3E8"
	}]
}'

curl --request POST \
  --url http://localhost:8080/rpc \
  --header 'content-type: application/json' \
  --data '{
	"id": 1,
	"method": "FundingService.Deposit",
	"params": [{
		"amount": "0x3E8"
	}]
}'

#curl --request POST \
#  --url http://localhost:8080/rpc \
#  --header 'content-type: application/json' \
#  --data '{
#	"id": 1,
#	"method": "FundingService.OpenChannel",
#	"params": [{
#	    "amount": "0x3E7",
#        "peerPubKey": "0x02ce7edc292d7b747fab2f23584bbafaffde5c8ff17cf689969614441e0527b900"
#	}]
#}'

echo "Testing Bob..."
curl --request POST \
  --url http://localhost:8081/rpc \
  --header 'content-type: application/json' \
  --data '{
	"id": 1,
	"method": "FundingService.Approve",
	"params": [{
		"amount": "0x3E8"
	}]
}'

echo "This will probably fail due to lack of funds..."
curl --request POST \
  --url http://localhost:8081/rpc \
  --header 'content-type: application/json' \
  --data '{
	"id": 1,
	"method": "FundingService.Deposit",
	"params": [{
		"amount": "0x3E8"
	}]
}'
