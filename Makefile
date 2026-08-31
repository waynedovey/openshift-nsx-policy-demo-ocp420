.PHONY: preflight discover import-windows setup show demo test manual reset cleanup

preflight:
	./scripts/preflight.sh

discover:
	./scripts/discover-boot-sources.sh

import-windows:
	@test -n "$(WINDOWS_IMAGE)" || (echo "Usage: make import-windows WINDOWS_IMAGE=/path/win2022.qcow2" && exit 2)
	./scripts/import-windows-image.sh "$(WINDOWS_IMAGE)"

setup:
	./scripts/setup.sh

show:
	./scripts/show-vms.sh

demo:
	./scripts/demo.sh

test:
	./scripts/test.sh final

manual:
	./scripts/manual-vm-tests.sh

reset:
	./scripts/reset-policies.sh

cleanup:
	./scripts/cleanup.sh
