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

function initDirectories {
    rm -rf ./output/listes
	mkdir -p ./output/listes
}

function checkInputFile {
    if [[ ! -f "$INPUT_FILE" ]]
    then
        echo "Le fichier $INPUT_FILE n'est pas présent, renommer le fichier téléchargé depuis HelloAsso !" >&2
        exit 1
    fi
}

function appendToMailingLists {
    champ=("$@")

    tarif=$(echo "${champ[11]}" | xargs | xargs) # "Inscriptions Enfant - Créneaux Vendredi" | "Inscriptions Enfant - Créneaux Mardi" | "Inscriptions ADULTES Grimpo6" | "Inscription Parent" | "Inscriptions Enfant - Créneaux NON ENCADRÉS"
    email=$(echo "${champ[21]}" | xargs)
    email_parent_1=$(echo "${champ[39]}" | xargs)
    email_parent_2=$(echo "${champ[40]}" | xargs)
    pole1="${champ[34]}"
    pole2="${champ[35]}"
    type_inscription=$(echo "${champ[18]}" | xargs | xargs) # "Nouveau" | "Réinscrit"
    case $tarif in
        "Inscriptions ADULTES Grimpo6")
            echo "${email}" | iconv -f UTF-8 -t ISO-8859-1 >> "output/listes/membres.csv"
            if [ "$type_inscription" == "Nouveau" ]
            then
                echo "${email}" | iconv -f UTF-8 -t ISO-8859-1 >> "output/listes/nouveaux.csv"
            fi
            if [ "$type_inscription" == "Réinscrit" ]
            then
                echo "${email}" | iconv -f UTF-8 -t ISO-8859-1 >> "output/listes/reinscrits.csv"
            fi
        ;;
        "Inscription Parent")
            echo "${email}" | iconv -f UTF-8 -t ISO-8859-1 >> "output/listes/membres.csv"
        ;;
        "Inscriptions Enfant - Créneaux Vendredi")
            echo "${email_parent_1}" | iconv -f UTF-8 -t ISO-8859-1 >> "output/listes/parents_vendredi.csv"
            echo "${email_parent_1}" | iconv -f UTF-8 -t ISO-8859-1 >> "output/listes/parents.csv"
            if [ "$email_parent_2" != "" ]
            then
                echo "${email_parent_2}" | iconv -f UTF-8 -t ISO-8859-1 >> "output/listes/parents_vendredi.csv"
                echo "${email_parent_2}" | iconv -f UTF-8 -t ISO-8859-1 >> "output/listes/parents.csv"
            fi
        ;;
        "Inscriptions Enfant - Créneaux Mardi")
            echo "${email_parent_1}" | iconv -f UTF-8 -t ISO-8859-1 >> "output/listes/parents_mardi.csv"
            echo "${email_parent_1}" | iconv -f UTF-8 -t ISO-8859-1 >> "output/listes/parents.csv"
            if [ "$email_parent_2" != "" ]
            then
                echo "${email_parent_2}" | iconv -f UTF-8 -t ISO-8859-1 >> "output/listes/parents_mardi.csv"
                echo "${email_parent_2}" | iconv -f UTF-8 -t ISO-8859-1 >> "output/listes/parents.csv"
            fi
        ;;
        "Inscriptions Enfant - Créneaux NON ENCADRÉS")
            echo "${email_parent_1}" | iconv -f UTF-8 -t ISO-8859-1 >> "output/listes/parents_non_encadre.csv"
            echo "${email_parent_1}" | iconv -f UTF-8 -t ISO-8859-1 >> "output/listes/parents.csv"
            if [ "$email_parent_2" != "" ]
            then
                echo "${email_parent_2}" | iconv -f UTF-8 -t ISO-8859-1 >> "output/listes/parents_non_encadre.csv"
                echo "${email_parent_2}" | iconv -f UTF-8 -t ISO-8859-1 >> "output/listes/parents.csv"
            fi
        ;;
    esac

    # Écrire le mail dans un fichier pour chaque Pole
    # Au moins avec mon PC (ancienne version excel), sans convertir en ISO Excel ne détecte pas l'UTF-8
    # Sinon supprimer le | iconv ...
    if [[ -n "$pole1" ]]
    then
        nom_fichier_pole=$(echo "$pole1" | tr -d '-' | tr -s ' ' '_')
        echo "${email}" | iconv -f UTF-8 -t ISO-8859-1 >> "output/listes/${nom_fichier_pole}.csv"
    fi
    if [[ -n "$pole2" ]]
    then
        nom_fichier_pole=$(echo "$pole2" | tr -d '-' | tr -s ' ' '_')
        echo "${email}" | iconv -f UTF-8 -t ISO-8859-1 >> "output/listes/${nom_fichier_pole}.csv"
    fi
}

initDirectories
checkInputFile

nb_lignes=$(($(wc -l < "$INPUT_FILE") - 1))
ligne=0

# Lire toutes les lignes sauf la premiere
tail -n +2 "$INPUT_FILE" | while IFS=';' read -r -a champ
do
    ligne=$((ligne + 1))
    echo -ne "\rTraitement de $ligne lignes sur $nb_lignes"

    email=$(echo "${champ[21]}" | xargs)

    if [ "$email" != "" ]
    then
        if [ -f "ignore.csv" ] && grep -q -i "$email" "ignore.csv"
        then
            echo "ignore: $email"
            continue
        fi

        if [ -f "fake_new.csv" ] && grep -q -i "$email" "fake_new.csv"
        then
            echo "fake_new: $email"
            champ[11]="Réinscriptions ADULTES"
        fi

        if [ -f "fake_old.csv" ] && grep -q -i "$email" "fake_old.csv"
        then
            echo "fake_old: $email"
            champ[11]="Inscriptions ADULTES Grimpo6"
        fi

        if [ -f "switch_mail.csv" ] && grep -q -i "$email" "switch_mail.csv"
        then
            champ[21]=$(grep -i "$email" "switch_mail.csv" | cut -d ',' -f2 | xargs)
            echo "switch_mail: $email: ${champ[21]}"
        fi
    fi

    appendToMailingLists "${champ[@]}"
done
printf "\n"
