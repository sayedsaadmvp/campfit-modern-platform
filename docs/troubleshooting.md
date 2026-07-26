# Troubleshooting

- If `python.exe` is unavailable on Windows, verify the Python installation path before validating the analytics service locally.
- If Container Apps cannot pull images, verify the user-assigned identity has `AcrPull`.
- If Key Vault loading fails, verify `KEY_VAULT_URI` and `USER_ASSIGNED_IDENTITY_CLIENT_ID`.
