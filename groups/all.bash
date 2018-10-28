DATASETS=()
for i in tests/*.oat;
do
	DATASETS+=($(basename $i .oat))
done
