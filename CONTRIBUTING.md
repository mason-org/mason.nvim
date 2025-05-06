-   [Contribution policy](#contribution-policy)
-   [Adding a new package](#adding-a-new-package)
-   [Code style](#code-style)
-   [Generated code](#generated-code)
-   [Tests](#tests)
-   [Adding or changing a feature](#adding-or-changing-a-feature)
-   [Commit style](#commit-style)
-   [Pull requests](#pull-requests)

# Contribution policy

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT
RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in [BCP 14][bcp14],
[RFC2119][rfc2119], and [RFC8174][rfc8174] when, and only when, they appear in all capitals, as shown here.

[bcp14]: https://tools.ietf.org/html/bcp14
[rfc2119]: https://tools.ietf.org/html/rfc2119
[rfc8174]: https://tools.ietf.org/html/rfc8174

# Adding a new package

Core `mason.nvim` package definitions reside within the [`github:mason-org/mason-registry`
registry](https://github.com/mason-org/mason-registry/). Contributions to add new packages MUST be done there (refer to
the README and existing package definitions).

# Code style

This project adheres to Editorconfig, Selene, and Stylua code style & formatting rules. New patches MUST adhere to these
coding styles.

# Generated code

Some changes such as adding or changing a package definition will require generating some new code. The changes to
generated code MAY be included in a pull request. If it's not included in a pull request, it will automatically be
generated and pushed to your branch before merge.

Generating code can be done on Unix systems like so:

```sh
make generate
```

# Tests

[Tests](https://github.com/mason-org/mason.nvim/tree/main/tests) MAY be added or modified to reflect any new changes.
Tests can be executed on Unix systems like so:

```sh
make test
FILE=tests/mason-core/managers/luarocks_spec.lua make test
```

# Adding or changing a feature

Adding or changing a feature MUST be preceded with an issue where scope and acceptance criteria are agreed upon with
project maintainers before implementation.

# Commit style

Commits SHOULD follow the [conventional commits guidelines](https://www.conventionalcommits.org/en/v1.0.0/).

# Pull requests

Once a pull request is marked as ready for review (i.e. not in draft mode), new changes SHOULD NOT be force-pushed to
the branch. Merge commits SHOULD be preferred over rebases.
