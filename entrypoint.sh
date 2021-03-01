#!/bin/bash -l

# get latest cod-tools

#apt-get update

#apt-get -y install cod-tools

# run the checks
# any output from cif_ddlm_dic_check flags
# a problem, the grep for ":" just makes
# sure that all lines are output.

shopt -s nullglob
for file in ./*.dic
do	
	echo $file
	if  (cif_ddlm_dic_check $file | grep ":") 
then echo "Failure"; exit 1;
fi
done
