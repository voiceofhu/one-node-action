.PHONY: check

check:
	sh -n install.sh uninstall.sh tests/scripts_test.sh
	./tests/scripts_test.sh
