#!/bin/bash
#
# Synchronise les liste mail OVH avec les adresses présentes dans
# les fichiers produits par ./generate_mailing_list.sh dans output/listes/

set -eu

source .env

OVH_DOMAIN="grimpo6.org"

# L'authentification auprès de l'API est compliquée, d'où cette function dédiée.
function ovhRequest {
    method="$1"
    chemin="$2"
    body="${3:-}"

    url="https://api.eu.ovhcloud.com/v1$chemin"
    timestamp=$(date +%s)

    # $1$ + sha1(AS+CK+METHOD+URL+BODY+TIMESTAMP)
    signature=$(
        printf '%s+%s+%s+%s+%s+%s' \
            "$OVH_APPLICATION_SECRET" \
            "$OVH_CONSUMER_KEY" \
            "$method" \
            "$url" \
            "$body" \
            "$timestamp" \
        | sha1sum | cut -d ' ' -f 1
    )

    if [[ -n "$body" ]]
    then
        curl_body="--data-binary $body"
    else
        curl_body=""
    fi

    curl "$url" \
        --silent \
        --request "$method" \
        --header 'Content-Type: application/json' \
        --header "X-Ovh-Application: $OVH_APPLICATION_KEY" \
        --header "X-Ovh-Consumer: $OVH_CONSUMER_KEY" \
        --header "X-Ovh-Timestamp: $timestamp" \
        --header "X-Ovh-Signature: \$1\$$signature" \
        $curl_body
}

function getSubscribers {
    list=$1
    ovhRequest GET "/email/domain/$OVH_DOMAIN/mailingList/$list/subscriber" | jq -r '.[]' | sort -u
}

function addSubscriber {
    list=$1
    email=$2

    body="{\"email\":\"$email\"}"

    ovhRequest POST "/email/domain/$OVH_DOMAIN/mailingList/$list/subscriber" "$body" >> /dev/null
}

function removeSubscriber {
    list=$1
    email=$2

    body="{\"email\":\"$email\"}"

    ovhRequest DELETE "/email/domain/$OVH_DOMAIN/mailingList/$list/subscriber/$email" >> /dev/null
}

for list_file in output/listes/*.csv
do
    list_name=$(grep "^$(basename "$list_file")=" "lists_map.conf" | cut -d '=' -f2)

    current_subscribers=$(getSubscribers "$list_name" | tr '[:upper:]' '[:lower:]' | sort -u)
    expected_subscribers=$(tr '[:upper:]' '[:lower:]' < "$list_file" | sort -u)

	if [[ $list_name == "" ]]
	then
    	echo "- $list_name - ATTENTION - Aucune liste associée à $list_file"
		continue
	fi

    echo "- $list_name ($(echo "$expected_subscribers" | wc -l) vs $(echo "$current_subscribers" | wc -l))"

    for email in $expected_subscribers
    do
        if ! echo "$current_subscribers" | grep -q -F "$email"
        then
        	echo "    Ajout de $email à $list_name"
            addSubscriber "$list_name" "$email"
        fi
    done

    for email in $current_subscribers
    do
	    if ! echo "$expected_subscribers" | grep -q -F "$email"
	    then
			echo "    Suppression de $email à $list_name"
	        removeSubscriber "$list_name" "$email"
	    fi
    done
done

