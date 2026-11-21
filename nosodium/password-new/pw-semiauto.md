# `pw-semiauto.ps1` usage guide

`pw-semiauto.ps1` resets selected local and Active Directory (AD) account passwords on a Windows machine. It generates a different passphrase for each account, previews the accounts that would change, and requires you to type **`RESET`** before making any changes. It writes successful credentials to a protected file under `C:\CCDC\PCRs`.

Run it directly in an interactive Windows PowerShell 5.1 or later session from the directory containing the script. Local password changes require an elevated session. AD changes require the ActiveDirectory module, domain connectivity, and permission to reset the selected accounts.

## Parameters at a glance

| Parameter | What it does |
| --- | --- |
| `-LocalUsers 'alice','bob'` | Selects named local users on this machine. |
| `-DomainUsers 'alice','bob'` | Selects named AD users by an identity accepted by `Get-ADUser -Identity`. |
| `-LocalUsersFile path` | Reads local usernames from a text file, one per line. |
| `-DomainUsersFile path` | Reads AD usernames from a text file, one per line. |
| `-ExcludeServiceAccounts` | Skips AD accounts with an SPN. Local accounts are unaffected. Used alone, it discovers users and asks `y/n` for each remaining account. |
| `-AllExcept 'Local\Guest,CORP\svc'` or `-AllExcept path` | Discovers users and selects everyone except qualified names in the comma-separated list or text file. Skips individual `y/n` prompts but still requires the final `RESET`. |
| `-ForceChangeAtLogon` | Requires successfully reset AD users to change passwords at next logon. |
| `-SetPasswordNeverExpires` | Sets that property for successfully reset AD users; the default leaves it unchanged. |

**Combinations:** `-AllExcept` cannot be combined with `-LocalUsers`, `-DomainUsers`, `-LocalUsersFile`, or `-DomainUsersFile`. The four explicit-selection options can be combined with each other. `-ForceChangeAtLogon` cannot be used when the final selection includes any local users. `-ExcludeServiceAccounts` works with either selection mode. AD-setting switches such as `-SetPasswordNeverExpires` need explicit targets or `-AllExcept`; supplying one by itself does not start discovery.

## Choose accounts

### Prompt for each discovered account

```powershell
.\pw-semiauto.ps1
```

With no parameters, the script discovers local accounts and, when the machine is domain joined and AD can be queried, domain accounts. It asks `y/n` for each account. After those choices, it displays the selected accounts and asks you to type `RESET` once for the whole selection. Answering anything else stops without changing passwords or creating a credential file.

To omit AD accounts with Service Principal Names (SPNs) from those prompts:

```powershell
.\pw-semiauto.ps1 -ExcludeServiceAccounts
```

The SPN filter does not exclude local accounts. The script does not infer service accounts from their names or from `PasswordNeverExpires`.

### Supply specific usernames or files

```powershell
.\pw-semiauto.ps1 -LocalUsers 'labuser1','labuser2'
.\pw-semiauto.ps1 -DomainUsers 'alice','bob' -ExcludeServiceAccounts
.\pw-semiauto.ps1 -LocalUsersFile 'C:\CCDC\PCRs\local-users.txt' -DomainUsersFile 'C:\CCDC\PCRs\domain-users.txt'
```

`-LocalUsers` and `-DomainUsers` accept lists. The matching `-LocalUsersFile` and `-DomainUsersFile` options accept text files with one username per line. You can combine names and files; blank lines and lines beginning with `#` are ignored, and duplicate names within each account type are removed without regard to case. For AD names, use an identity accepted by `Get-ADUser -Identity`, such as a `sAMAccountName`. Selected accounts are resolved before the preview. Unknown accounts cause an error.

### Select everyone except named accounts

```powershell
.\pw-semiauto.ps1 -AllExcept 'Local\Guest,CORP\scoring_svc' -ExcludeServiceAccounts
.\pw-semiauto.ps1 -AllExcept 'C:\CCDC\PCRs\exclude.txt'
```

`-AllExcept` discovers all local and available AD users, removes the named exclusions, and previews every remaining account. It skips the per-account `y/n` questions, so review the entire preview carefully. It still requires the typed `RESET` confirmation before any password changes.

The value may be a comma-separated list or the path to an existing text file. A file contains one qualified account per line; blank lines and `#` comments are ignored. Use `Local\name` or `.\name` for a local account, and the domain's NetBIOS prefix (for example, `CORP\name`) for an AD account. Matching is case-insensitive. Every exclusion must match a discovered account; a typo, missing file, or empty exclusion list stops the run. Do not combine `-AllExcept` with explicit username or username-file parameters.

In this batch mode, local discovery, domain membership detection, or AD discovery errors stop the run before confirmation. On a machine that is not domain joined, only local accounts are discovered.

## Optional AD settings

`-ForceChangeAtLogon` marks successfully reset AD users to change their passwords at next logon. It is incompatible with a run that includes local targets. `-SetPasswordNeverExpires` sets that AD property after a successful reset. Without these switches, the script leaves those properties unchanged. If a property update fails after the password reset, the script warns you; the password may already have changed.

## Confirmation and credential output

After the final preview, type the exact uppercase word `RESET` to proceed. The script creates a timestamped `pwreset_*.csv` file in `C:\CCDC\PCRs` only after confirmation. It first restricts the file ACL to the executing account and local Administrators. If it cannot prepare the protected file, it stops before resetting accounts.

Each successful reset produces a line with **no header**:

```text
labuser1,BraveOtter42!
CORP\alice,SwiftFalcon17!
```

The displayed passwords above illustrate the file format; actual passwords are generated randomly in `AdjectiveAnimal##!` form. The console reports account-level success or failure and the output path, but does not print the passwords. Failed resets are removed from the credential file when possible. The output contains plaintext credentials, so restrict access to it and move the credentials into your approved password storage promptly.

The script does not automatically skip disabled accounts, your current account, or other special accounts. In `-AllExcept` mode, name any accounts you intend to protect in the exclusion list and review the preview before confirming.
