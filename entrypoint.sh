#!/bin/bash -l

# get latest cod-tools

apt-get install cod-tools

# run the checks
popd

shopt -s nullglob
for file in ./*.dic
do	
if !(cif_ddlm_dic_check $file )
then echo "Failure"; exit 1;
fi
done
