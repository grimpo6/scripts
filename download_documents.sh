#!/bin/bash
#
# 27/08/25 v 1.2 - Avec xargs on supprime les espaces et autres en debut/fin lors de la saisie du champ
#                  et on écrit le tout dans le fichier de sortie
# 07/09/25 v 1.3 - Création de functions pour clarifier le code
#                - Ajout de liste mails membres, parents, parents_*, réinscrits, nouveaux
#                - Ajout de l'affichage des parents non inscrits
#                - Detect le type de fichier avec le header Content-Type
# 19/09/25 v 1.4 - Ajout de la prise en compte des erreurs de mail.
# 14/07/26 v 1.5 - Modification des No de champs car changement format pour inscription 2026-27 et champ $18 'Type d'inscription=Nouveau/Réinscrit'
#                 - Renomme variable 'type_inscription' en 'tarif'
# Usage:
#   - Télécharger le fichier membres.csv depuis HelloAsso
#   - Indiquer le CLIENT_ID et CLIENT_SECRET
#   - Créer les fichiers ignore.csv, fake_new.csv, fake_old.csv, switch_mail.csv si besoin
#     - ignore.csv : liste des emails à ignorer (ex: blessés, personne changeant de club, etc.)
#     - fake_new.csv : liste des personnes qui ont loupé les réinscriptions.
#     - fake_old.csv : liste des nouveaux inscrits pendant les réinscriptions.
#     - switch_mail.csv : liste des personnes qui se sont trompé d'email. Format : ancien_email,nouvel_email
#
# Liste des champs utilisés (on commence à 0)
# 3 Nom adhérent
# 4 Prénom adhérent
# 11 Tarif ("Inscriptions Enfant - Créneaux Vendredi" | "Inscriptions Enfant - Créneaux Mardi" | "Inscriptions ADULTES Grimpo6" | "Inscription Parent" | "Inscriptions Enfant - Créneaux NON ENCADRÉS")
# 18 Type d'inscription (= "Nouveau" | "Réinscrit" --> pour distinguer Inscription Adulte)
# 21 Email - ATTENTION à l'orthographe du mail - éviter les adresses en @yahoo.fr
# 26 Attestation médicale "FSGT majeurs" (--> URL)
# 27 Champ Enfant: Attestation médicale "FSGT mineurs" 
# 30 Certificat médical (en cas de réponse positive à au moins une rubrique du questionnaire de santé) (--> URL)
# 34 Pôle n°1 (obligatoire, et oui, c'est une association de bénévoles, on s'engage à s'impliquer en s'inscrivant) (--> URL)
# 35 Pôle n°2 (facultatif) 
# 39 Champ Parent: Email du parent - ATTENTION à l'orthographe du mail - éviter les mails en @yahoo.fr
# 40 Champ Parent: Email du parent 2
# 43 Champ Parent: J'ai compris que l'inscription d'au moins 1 parent est obligatoire (Oui/Non)
# 44 Champ Parent: G6 est une association ... je m’engage à suivre la formation qui sera donnée pour pouvoir assurer la sécurité des enfants (Oui/Non)
# 45 Champ Parent: En inscrivant mon enfant, je m’engage à m’inscrire 1 semaine sur 3 sur le planning pour participer à l'encadrement de la séance (Oui/Non)

set -eu

source .env

INPUT_FILE="membres.csv"
OUTPUT_FILE="membres_local.csv"

function getAccessToken {
    if [ "$CLIENT_ID" == "" ] || [ "$CLIENT_SECRET" == "" ]
    then
        echo "Le client ID ou le client secret est vide." >&2
        echo "Génère les sur le site de helloasso.com, et remplace les dans le fichier .env." >&2
        echo "https://admin.helloasso.com/grimpo6/integrations" >&2
        exit 1
    fi

    response=$(
        curl --request POST \
        --url https://api.helloasso.com/oauth2/token \
        --header 'accept: application/json' \
        --header 'content-type: application/x-www-form-urlencoded' \
        --data-urlencode grant_type=client_credentials \
        --data-urlencode client_id=$CLIENT_ID \
        --data-urlencode client_secret=$CLIENT_SECRET
    )

    access_token=$(echo "$response" | jq -r '.access_token')

    if [[ "$access_token" == "null" || -z "$access_token" ]]
    then
        echo "Erreur lors de la récupération du token: $error_description" >&2
        exit 1
    fi

    echo "$access_token"
}

function checkInputFile {
    if [[ ! -f "$INPUT_FILE" ]]
    then
        echo "Le fichier $INPUT_FILE n'est pas présent, renommer le fichier téléchargé depuis HelloAsso !" >&2
        exit 1
    fi
}

function validateEntry {
    champ=("$@")

    inscription_parent="${champ[43]}"
    formation_parent="${champ[44]}"
    pole_parent="${champ[45]}"

    # On cherche des Warnings (a completer pour d'autres (enfant sans parent ar exemple ...))
    if [[ "$inscription_parent" == "Non" || "$formation_parent" == "Non" || "$pole_parent" == "Non" ]]
    then
        echo -e "\n \n /!\ Attention : inscription enfant, le parent a répondu Non à une des questions (formation, inscription ou Pole) ligne $((ligne + 1)) ! \n" >&2
        champ[2]="/!\ Vérifier l'engagement des parents"
    fi

    email=$(echo "${champ[21]}" | xargs)
    tarif=$(echo "${champ[11]}" | xargs | xargs) # "Inscriptions Enfant - Créneaux Vendredi" | "Inscriptions Enfant - Créneaux Mardi" | "Inscriptions ADULTES Grimpo6" | "Inscription Parent" | "Inscriptions Enfant - Créneaux NON ENCADRÉS"

    if [[ "$email" == "" && ( "$tarif" == "Inscriptions ADULTES Grimpo6" ) ]]
    then
        echo -e "\n \n /!\ Attention : Champ email non renseigné ligne $((ligne + 1)) ! \n" >&2
        champ[2]="/!\ Vérifier l'email de la personne"
    fi
}

function downloadDocument {
    url=$1
    repertoire=$2
    nom_base=$3

    # Early return si l'url est vide
    if [ "$url" == "" ]
    then
        return
    fi

    chemin="${repertoire}/${nom_base}"

    # Early return si le document est déjà téléchargé
    for ext in jpg pdf gif png
    do
        if [ -f "$chemin.$ext" ]
        then
            return
        fi
    done

    contentType="$(
    	curl "$url" \
    		-v \
    		--location \
    		-H "Authorization: Bearer $(getAccessToken)" \
    		--output "$chemin" 2>&1 \
        | grep -i '< content-type: ' | cut -d ':' -f2 | tr -d '[:space:]'
    )"

    case "$contentType" in
        "image/jpeg") ext="jpg" ;;
        "application/pdf") ext="pdf" ;;
        "image/gif") ext="gif" ;;
        "image/png") ext="png" ;;
        *) ext="foo" ;;
    esac

    # On renomme avec l'extension trouvée
    mv "$chemin" "$chemin.$ext"
}

function appendToNewFile {
    champ=("$@")

    # Remplacer les colonnes dans la ligne du fichier new avec les liens et les nom/prénom/mail sans espace
    champ[3]="$nom"
    champ[4]="$prenom"
    champ[21]=$(echo "${champ[21]}" | xargs)
    champ[26]="=HYPERLINK(\"$nom_attestation\")"
    champ[27]="=HYPERLINK(\"$nom_attestation_enfant\")"
    champ[30]="=HYPERLINK(\"$nom_certif_med\")"

    # Réécrire la ligne complete avec hyperlink locaux dans le nouveau fichier
    IFS=';' ; echo "${champ[*]}" >> "$OUTPUT_FILE"
}

function validateParents {
    echo "Liste des adresses mails de parents d'enfants non présentes dans la liste membres"

    tail -n +2 "$INPUT_FILE" | while IFS=';' read -r -a champ; do
        nom=$(echo "${champ[3]}" | xargs | xargs )
        prenom=$(echo "${champ[4]}" | xargs | xargs )
        tarif=$(echo "${champ[11]}" | xargs | xargs)
        email_parent_1=$(echo "${champ[39]}" | xargs)
        email_parent_2=$(echo "${champ[40]}" | xargs)


        case $tarif in
            "Inscriptions Enfant - Créneaux Vendredi")
                if ! cat output/listes/membres.csv | grep --quiet "$email_parent_1"
                then
                    if ! cat output/listes/membres.csv | grep --quiet "$email_parent_2"
                    then
                        echo "- $prenom $nom (Vendredi)"
                        echo "  - $email_parent_1"
                        echo "  - $email_parent_2"
                    fi
                fi
            ;;
            "Inscriptions Enfant - Créneaux Mardi")
                if ! cat output/listes/membres.csv | grep --quiet "$email_parent_1"
                then
                    if ! cat output/listes/membres.csv | grep --quiet "$email_parent_2"
                    then
                        echo "- $prenom $nom (Mardi)"
                        echo "  - $email_parent_1"
                        echo "  - $email_parent_2"
                    fi
                fi
            ;;
        esac
    done
}

ACCESS_TOKEN=$(getAccessToken)

checkInputFile

# Creation des repertoires contenant les fichiers télécharges
mkdir -p ./output/attestations ./output/attestations_enfant ./output/certificats_med

nb_lignes=$(($(wc -l < "$INPUT_FILE") - 1))
ligne=0

# Lire nom des colonnes de membres.csv et l'écrire dans le fichier de sortie
head -n 1 "$INPUT_FILE" > "$OUTPUT_FILE"

# Lire toutes les lignes sauf la premiere
tail -n +2 "$INPUT_FILE" | while IFS=';' read -r -a champ
do
    ligne=$((ligne + 1))
    echo -ne "\rTéléchargement et traitement de $ligne lignes sur $nb_lignes"

    email=$(echo "${champ[21]}" | xargs)

    if [ "$email" != "" ]
    then
        if [ -f "ignore.csv" ] && grep -q -i "$email" "ignore.csv"
        then
            echo "ignore: $email"
            continue
        fi
    fi

    validateEntry "${champ[@]}"

    # Avec xargs on supprime les espaces et autres en debut/fin lors de la saisie du champ
    nom=$(echo "${champ[3]}" | xargs | xargs )
    prenom=$(echo "${champ[4]}" | xargs | xargs )

    # Télécharger attestation et certificats
    downloadDocument "${champ[26]}" "./output/attestations" "${prenom}_${nom}_attestation"
    nom_attestation=$(downloadDocument "${champ[26]}" "./output/attestations" "${prenom}_${nom}_attestation")
    nom_attestation_enfant=$(downloadDocument "${champ[27]}" "./output/attestations_enfant" "${prenom}_${nom}_attestation_enfant")
    nom_certif_med=$(downloadDocument "${champ[30]}" "./output/certificats_med" "${prenom}_${nom}_certif_med")

    appendToNewFile "${champ[@]}"
done
printf "\n"

validateParents
