#!/bin/bash -l

set -ue

# get latest cod-tools

apt-get update

apt-get -y install cod-tools

# install 'moreutils' since it contain the 'sponge' program 

apt-get -y install moreutils

# run the checks
# any output from cif_ddlm_dic_check flags
# a problem, the grep for ":" just makes
# sure that all lines are output.

shopt -s nullglob
OUT_FILE=$(mktemp)
ERR_FILE=$(mktemp)
for file in ./*.dic
do
    echo "$file"
    # Run the checks and report fatal errors
    cif_ddlm_dic_check "$file" > "${OUT_FILE}" 2> "${ERR_FILE}" || (
        echo "Execution of the 'cif_ddlm_dic_check' script failed with" \
             "the following errors:"
        cat "${ERR_FILE}"
        rm -rf "${OUT_FILE}" "${ERR_FILE}"
        exit 1
    )

    # Filter and report error messages
    #~ grep "${ERR_FILE}" -v \
    #~      -e "ignored message A" \
    #~      -e "ignored message B" |
    #~ sponge "${ERR_FILE}"
    if [ -s "${ERR_FILE}" ]
    then
        echo "Dictionary check generated the following non-fatal errors:"
        cat "${ERR_FILE}"
    fi

    # Filter and report output messages
    #~ grep "${OUT_FILE}" -v \
    #~     -e "ignored message A" \
    #~     -e "ignored message B" |
    #~ sponge "${OUT_FILE}"
    if [ -s "${OUT_FILE}" ]
    then
        echo "Dictionary check detected the following irregularities:";
        cat "${OUT_FILE}"
        rm -rf "${OUT_FILE}" "${ERR_FILE}"
        exit 1
    fi
done

rm -rf "${OUT_FILE}" "${ERR_FILE}"
