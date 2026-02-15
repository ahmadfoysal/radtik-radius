# Contributing to RadTik FreeRADIUS

Thank you for your interest in contributing to RadTik FreeRADIUS! This document provides guidelines for contributing to this project.

## How to Contribute

### Reporting Bugs

If you find a bug, please open an issue on GitHub with:

- **Clear title** describing the bug
- **Steps to reproduce** the issue
- **Expected behavior** vs actual behavior
- **Environment details** (OS version, FreeRADIUS version, Python version)
- **Log excerpts** if applicable

### Suggesting Enhancements

Enhancement suggestions are welcome! Please open an issue with:

- **Clear description** of the enhancement
- **Use case** explaining why it would be valuable
- **Proposed solution** if you have ideas

### Pull Requests

1. **Fork the repository** and create your branch from `main`
2. **Make your changes** with clear, descriptive commits
3. **Test thoroughly** on a clean Ubuntu 22.04 LTS installation
4. **Update documentation** (README, CHANGELOG) if needed
5. **Submit a pull request** with a clear description

### Code Style

#### Bash Scripts
- Use 4 spaces for indentation
- Add comments for complex sections
- Use descriptive variable names
- Include error handling with `set -e`
- Add colored output for user feedback

#### Python Scripts
- Follow PEP 8 style guide
- Use descriptive variable and function names
- Add docstrings to functions
- Handle exceptions gracefully
- Include informative error messages

### Testing

Before submitting a pull request:

1. **Test on clean Ubuntu 22.04 LTS**
   ```bash
   # Run the installer
   sudo bash install.sh
   
   # Run validation
   sudo bash validate.sh
   ```

2. **Test synchronization scripts**
   ```bash
   sudo python3 /opt/radtik-sync/sync-vouchers.py
   sudo python3 /opt/radtik-sync/check-activations.py
   sudo python3 /opt/radtik-sync/sync-deleted.py
   ```

3. **Test FreeRADIUS authentication**
   ```bash
   radtest testuser testpass localhost 0 testing123
   ```

### Commit Messages

Write clear, descriptive commit messages:

```
Add support for MySQL backend

- Add MySQL configuration templates
- Update install script to detect database type
- Update documentation with MySQL setup
```

### Documentation

- Update [README.md](README.md) for user-facing changes
- Update [CHANGELOG.md](CHANGELOG.md) following Keep a Changelog format
- Update inline code comments for technical changes
- Add examples for new features

## Development Setup

### Prerequisites

- Ubuntu 22.04 LTS (or VM/container)
- Git for version control
- Text editor (VS Code, Vim, etc.)

### Local Testing

```bash
# Clone your fork
git clone https://github.com/yourusername/radtik-radius.git
cd radtik-radius

# Make changes
# Test changes

# Commit
git add .
git commit -m "Your descriptive commit message"
git push origin your-branch-name
```

## Project Structure

```
radtik-radius/
├── install.sh              # Main installer
├── validate.sh             # Validation script
├── clients.conf            # RADIUS clients config
├── scripts/                # Python sync scripts
│   ├── sync-vouchers.py
│   ├── check-activations.py
│   ├── sync-deleted.py
│   └── config.ini.example
├── mods-available/         # FreeRADIUS modules
├── mods-config/            # Module configurations
├── sites-enabled/          # Virtual server configs
└── sqlite/                 # Database templates
```

## Questions?

Feel free to open an issue for:
- Clarification on contribution process
- Technical questions
- Feature discussions

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
