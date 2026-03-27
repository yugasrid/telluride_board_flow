#!/bin/bash
echo "*******************************************************in pre script"
echo $LD_LIBRARY_PATH
export LD_LIBRARY_PATH=
if [[ "$@" == *"ve2"* ]]
then
	deactivate
	source /proj/aiebuilds/tools/yoctosdk/latest/environment-setup-cortexa72-cortexa53-basecamp-linux
else
	source /proj/aiebuilds/ryzen-ai/vek280/armtools_latest/sdk/environment-setup-cortexa72-cortexa53-xilinx-linux
fi

echo "Value of after sdk $LD_LIBRARY_PATH "
echo $CC
