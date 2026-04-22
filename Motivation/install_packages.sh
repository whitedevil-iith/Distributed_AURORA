sudo apt update && sudo apt install g++ python3 cmake ninja-build wget

wget https://www.nsnam.org/releases/ns-allinone-3.47.tar.bz2
tar xfj ns-allinone-3.47.tar.bz2
rm ns-allinone-3.47.tar.bz2
cd ns-allinone-3.47/ns-3.47
./ns3 configure --enable-examples --enable-tests
./ns3 build