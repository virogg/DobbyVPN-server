rm -rf libs/

cd wireguard-go/
make
cd ../
cd amneziawg-go/
make
cd ../
cd amneziawg-tools/src/
make
cd ../../
mkdir libs
cp wireguard-go/wireguard-go libs/
cp amneziawg-go/amneziawg-go libs/
cp amneziawg-tools/src/wg libs/awg
