# Legacy tests

These tests are preserved as historical references only. They target the removed or currently unsupported gateway-minimal/gateway-resilient profile interface and the optional DNS/SNI steering path. They are intentionally excluded from the supported CI suite and should not be treated as acceptance tests for the current dev branch.

The supported validation entrypoint is tests/test-local.sh. DNS/SNI steering must not be enabled or relied on until its installer, firewall rules, runtime behavior, and end-to-end tests are brought back into alignment.
