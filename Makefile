.PHONY: validate preflight setup refresh redeploy-windows demo test reset cleanup show paths doctor discover import-windows

validate:
	./scripts/validate-repo.sh

preflight:
	./scripts/preflight.sh

setup:
	./scripts/setup.sh

refresh:
	./scripts/refresh-policy-demo.sh

redeploy-windows:
	./scripts/redeploy-windows.sh

demo:
	./scripts/demo.sh

test:
	./scripts/test.sh final

reset:
	./scripts/reset-policies.sh

cleanup:
	./scripts/cleanup.sh

show:
	./scripts/show-vms.sh

paths:
	./scripts/show-policy-paths.sh

doctor:
	./scripts/doctor.sh

discover:
	./scripts/discover-boot-sources.sh

import-windows:
	@test -n "$(WINDOWS_IMAGE)" || (echo "Usage: make import-windows WINDOWS_IMAGE=/path/to/generalized-win2022.qcow2"; exit 2)
	./scripts/import-windows-image.sh "$(WINDOWS_IMAGE)"
