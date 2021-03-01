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
    # Run the checks
    cif_ddlm_dic_check "$file" > "${OUT_FILE}" 2> "${ERR_FILE}"

    # Filter out insignificant error messages:
    # grep -v -e 'pattern 1' -e "pattern 2" "${ERR_FILE}" | sponge "${ERR_FILE}"
    if [ -s "${ERR_FILE}" ]
    then
        echo "Dictionary check generated the following non-fatal errors:"
        cat "${ERR_FILE}"
    fi

    # Filter out insignificant output messages:
    # grep -v -e 'pattern a' -e "pattern b" "${OUT_FILE}" | sponge "${OUT_FILE}"
    if [ -s "${OUT_FILE}" ]
    then
        echo "Dictionary check detected the following irregularities:";
        cat "${OUT_FILE}"
        rm -rf "${OUT_FILE}" "${ERR_FILE}"
        exit 1;
    fi
done

rm -rf "${OUT_FILE}" "${ERR_FILE}"
