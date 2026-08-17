.PHONY: test example

test:
	./tests/test-check-bind.sh

example:
	./bin/check-bind --address 127.0.0.1 --port 8080 --snapshot examples/ss-localhost.txt
