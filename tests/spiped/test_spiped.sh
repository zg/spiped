#!/bin/sh

# This test script requires three ports.
src_port=8000
mid_port=8001
dst_port=8002

# output directory
out="output-tests-spiped"

# timing commands
sleep_ncat_start=1
sleep_valgrind_spiped_start=2
sleep_ncat_valgrind_stop=1
sleep_ncat_timeout_valgrind_stop=3

# Find script directory, and then relative spiped binary path.
scriptdir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
spiped_binary=$scriptdir/../../spiped/spiped

# Find system spiped if it supports -1
system_spiped_binary=`which spiped`
if [ -n "$system_spiped_binary" ]; then
	if $system_spiped_binary -1 2>&1 >/dev/null | grep -q "invalid option"; then
		# disable test
		system_spiped_binary=""
	fi
fi

# Check for required commands
if ! command -v ncat >/dev/null 2>&1; then
	echo "ncat not detected; it is part of the nmap suite"
	echo "	(it is required for multiple sockets on the same port)"
	exit 1
fi

# Check for optional commands
if ! command -v valgrind >/dev/null 2>&1; then
	echo "valgrind not detected: disabling memory checking"
	use_valgrind=""
else
	use_valgrind="1"
fi


check_leftover_server() {
	# Repeated testing, especially when doing ctrl-c to break out of
	# (suspected) hanging, can leave a ncat server floating around, which
	# is problematic for the next testing run.  Checking for this
	# shouldn't be necessary for normal testing (as opposed to test-script
	# development), but there's no harm in checking anyway.
	leftover=""

	# Find old ncat server
	cmd="ncat -k -l $dst_port"
	oldpid=`ps ax | grep "$cmd" | grep -v "grep" | cut -f2 -d " "`
	if [ ! -z $oldpid ]; then
		echo "Error: Left-over server from previous run: pid= $oldpid"
		leftover="1"
	fi

	# Early exit if any previous servers found
	if [ ! -z $leftover ]; then
		echo "Exit from left-over servers"
		exit 1
		echo "why am I reading this?"
	fi
}


####################################################

# set up a spiped "encryption" server
setup_spiped_encryption_server () {
	basename=$1
	check_leftover_server

	# set up valgrind command (if required)
	if [ -n "$use_valgrind" ]; then
		valgrind="valgrind --log-file=$out/$basename.val \
			--leak-check=full --show-leak-kinds=all "
	else
		valgrind=""
	fi

	# start backend server
	nc_pid="$(dst_port=$dst_port sh -c \
		'ncat -k -l $dst_port >/dev/null 2>&1 & echo ${!}' )"
	sleep $sleep_ncat_start

	# start spiped to connect source port to backend
	( $valgrind \
		$spiped_binary -e \
	 	-s 127.0.0.1:$src_port -t 127.0.0.1:$dst_port \
		-k $scriptdir/keys-blank.txt -F -1 -o 1 \
	; echo $? >> $out/$basename.ret ) &
	sleep $sleep_valgrind_spiped_start
}

# set up spiped "encryption" and "decryption" servers
setup_spiped_encryption_decryption_servers () {
	basename=$1
	check_leftover_server

	# set up valgrind commands (if required)
	if [ -n "$use_valgrind" ]; then
		valgrind_e="valgrind --log-file=$out/$basename-e.val \
			--leak-check=full --show-leak-kinds=all "
		valgrind_d="valgrind --log-file=$out/$basename-d.val \
			--leak-check=full --show-leak-kinds=all "
	else
		valgrind_e=""
		valgrind_d=""
	fi

	# start backend server
	nc_pid="$(dst_port=$dst_port outfile=$out/$basename.txt sh -c \
		'ncat -k -l -o $outfile $dst_port >/dev/null \
		2>&1 & echo ${!}' )"
	sleep $sleep_ncat_start

	# start spiped servers to connect source to mid, and mid to dest ports
	( $valgrind_e \
		$spiped_binary -e \
		-s 127.0.0.1:$src_port -t 127.0.0.1:$mid_port \
		-k $scriptdir/keys-blank.txt -F -1 -o 1 \
	; echo $? >> $out/$basename-e.ret ) &
	( $valgrind_d \
		$spiped_binary -d \
		-s 127.0.0.1:$mid_port -t 127.0.0.1:$dst_port \
		-k $scriptdir/keys-blank.txt -F -1 -o 1 \
	; echo $? >> $out/$basename-d.ret ) &
	sleep $sleep_valgrind_spiped_start
}

# set up spiped "encryption" and "decryption" servers, with the "decryption"
# server being the system
setup_spiped_encryption_decryption_servers_system () {
	basename=$1
	check_leftover_server

	# set up valgrind commands (if required)
	if [ -n "$use_valgrind" ]; then
		valgrind_e="valgrind --log-file=$out/$basename-e.val \
			--leak-check=full --show-leak-kinds=all "
		valgrind_d="valgrind --log-file=$out/$basename-d.val \
			--leak-check=full --show-leak-kinds=all "
	else
		valgrind_e=""
		valgrind_d=""
	fi

	# start backend server
	nc_pid="$(dst_port=$dst_port outfile=$out/$basename.txt sh -c \
		'ncat -k -l -o $outfile $dst_port >/dev/null \
		2>&1 & echo ${!}' )"
	sleep $sleep_ncat_start

	# start spiped servers to connect source to mid, and mid to dest ports
	( $valgrind_e \
		$spiped_binary -e \
		-s 127.0.0.1:$src_port -t 127.0.0.1:$mid_port \
		-k $scriptdir/keys-blank.txt -F -1 -o 1 \
	; echo $? >> $out/$basename-e.ret ) &
	( $valgrind_d \
		$system_spiped_binary -d \
		-s 127.0.0.1:$mid_port -t 127.0.0.1:$dst_port \
		-k $scriptdir/keys-blank.txt -F -1 -o 1 \
	; echo $? >> $out/$basename-d.ret ) &
	sleep $sleep_valgrind_spiped_start
}


####################################################

test_connection_open_close_single () {
	# Goal of this test:
	# - establish a connection to a spiped server
	# - open a connection, but don't say anything
	# - close the connection
	# - server should quit (because we gave it -1)
	basename="01-single-open-close"
	printf "Running test: $basename... "
	setup_spiped_encryption_server $basename
	echo "" | nc 127.0.0.1 $src_port
	# wait for spiped (and valgrind) to complete
	sleep $sleep_ncat_valgrind_stop
	kill $nc_pid
	wait
	# check results
	if [ `cat $out/$basename.ret` ]; then
		echo "PASSED!"
		retval=0
	else
		echo "FAILED!"
		retval=1
	fi
	return "$retval"
}


test_connection_open_timeout_single () {
	# Goal of this test:
	# - establish a connection to a spiped server
	# - open a connection, but don't say anything
	# - the connection should be closed automatically
	# - server should quit (because we gave it -1)
	basename="02-single-open"
	printf "Running test: $basename... "
	setup_spiped_encryption_server $basename
	nc 127.0.0.1 $src_port &
	# wait for spiped (and valgrind) to complete
	sleep $sleep_ncat_timeout_valgrind_stop
	kill $nc_pid
	wait
	# check results
	if [ `cat $out/$basename.ret` ]; then
		echo "PASSED!"
		retval=0
	else
		echo "FAILED!"
		retval=1
	fi
	return "$retval"
}


test_connection_open_close_double () {
	# Goal of this test:
	# - create a pair of spiped servers (encryption, decryption)
	# - open two connections, but don't say anything
	# - close one of the connections
	# - server should quit (because we gave it -1)
	basename="03-double-open-close"
	printf "Running test: $basename... "
	setup_spiped_encryption_decryption_servers $basename
	# awkwardly force nc to keep the connection open; the simple
	# "nc -q 2 ..." to wait 2 seconds isn't portable
	( ( echo ""; sleep 2 ) | nc 127.0.0.1 $src_port ) &
	echo "" | nc 127.0.0.1 $src_port
	# wait for spiped (and valgrind) to complete
	sleep $sleep_ncat_valgrind_stop
	kill $nc_pid
	wait
	# check results
	retval=0
	if [ ! `cat $out/$basename-e.ret` ]; then
		retval=1
	fi
	if [ ! `cat $out/$basename-d.ret` ]; then
		retval=1
	fi
	if [ "$retval" -eq 0 ]; then
		echo "PASSED!"
	else
		echo "FAILED!"
	fi
	return "$retval"
}


test_send_data () {
	# Goal of this test:
	# - create a pair of spiped servers (encryption, decryption)
	# - establish a connection to the encryption spiped server
	# - open one connection, send lorem-send.txt, close the connection
	# - server should quit (because we gave it -1)
	# - the received file should match lorem-send.txt
	basename="04-send-data"
	printf "Running test: $basename... "
	setup_spiped_encryption_decryption_servers $basename
	cat $scriptdir/lorem-send.txt | nc 127.0.0.1 $src_port
	# wait for spiped (and valgrind) to complete
	sleep $sleep_ncat_valgrind_stop
	kill $nc_pid
	wait
	# check results
	retval=0
	if [ ! `cat $out/$basename-e.ret` ]; then
		retval=1
	fi
	if [ ! `cat $out/$basename-d.ret` ]; then
		retval=1
	fi
	if ! cmp -s $scriptdir/lorem-send.txt "$out/$basename.txt" ; then
		retval=1
	fi
	if [ "$retval" -eq 0 ]; then
		echo "PASSED!"
	else
		echo "FAILED!"
	fi
	return "$retval"
}


test_send_data_system_spiped () {
	# Goal of this test:
	# - create a pair of spiped servers (encryption, decryption), where
	#   the decryption server uses the system-installed spiped binary
	# - establish a connection to the encryption spiped server
	# - open one connection, send lorem-send.txt, close the connection
	# - server should quit (because we gave it -1)
	# - the received file should match lorem-send.txt
	basename="05-send-data-system"
	printf "Running test: $basename... "
	if [ ! -n "$system_spiped_binary" ]; then
		echo "SKIP; no system spiped, or it is too old"
		return;
	fi
	setup_spiped_encryption_decryption_servers_system $basename
	cat $scriptdir/lorem-send.txt | nc 127.0.0.1 $src_port
	# wait for spiped (and valgrind) to complete
	sleep $sleep_ncat_valgrind_stop
	kill $nc_pid
	wait
	# check results
	retval=0
	if [ ! `cat $out/$basename-e.ret` ]; then
		retval=1
	fi
	if [ ! `cat $out/$basename-d.ret` ]; then
		retval=1
	fi
	if ! cmp -s $scriptdir/lorem-send.txt "$out/$basename.txt" ; then
		retval=1
	fi
	if [ "$retval" -eq 0 ]; then
		echo "PASSED!"
	else
		echo "FAILED!"
	fi
	return "$retval"
}


####################################################

# clean up previous
rm -rf $out
mkdir -p $out

# Run tests
test_connection_open_close_single &&		\
	test_connection_open_timeout_single &&	\
	test_connection_open_close_double &&	\
	test_send_data &&			\
	test_send_data_system_spiped
result=$?

if [ -n "$use_valgrind" ]; then
	echo
	echo "Valgrind memory-checking results are in $out/*.val"
fi

# Return value to Makefile
exit $result
