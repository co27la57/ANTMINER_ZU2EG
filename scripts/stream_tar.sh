cd /
printf './proc\n./sys\n./dev\n./run\n./lost+found\n./tmp\n' > /tmp/excl.txt
exec busybox tar cf - -X /tmp/excl.txt ./bin ./boot ./etc ./home ./lib ./media ./mnt ./root ./sbin ./usr ./var ./www ./config ./init
