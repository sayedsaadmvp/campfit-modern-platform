param(
    [string]$CommitMessage = "Update CampFit services",
    [string]$Branch = "main"
)

$ErrorActionPreference = "Stop"

$PlatformRoot = "C:\ssaad\CampFit\Development\campfit-modern-platform"

$Repositories = @(
    @{ Name = "CampFit Core API"; Path = "$PlatformRoot\services\campfit-core-api" },
    @{ Name = "CampFit BFF Mobile"; Path = "$PlatformRoot\services\campfit-bff-mobile" },
    @{ Name = "CampFit Adventure"; Path = "$PlatformRoot\services\campfit-adventure" }
)

function Invoke-Git {
    param([string]$RepositoryPath, [string[]]$Arguments)

    & git -C $RepositoryPath @Arguments

    if ($LASTEXITCODE -ne 0) {
        throw "Git failed in '$RepositoryPath': git $($Arguments -join ' ')"
    }
}

function Assert-GitRepository {
    param([string]$RepositoryPath)

    if (-not (Test-Path $RepositoryPath)) {
        throw "Repository path does not exist: $RepositoryPath"
    }

    & git -C $RepositoryPath rev-parse --is-inside-work-tree *> $null

    if ($LASTEXITCODE -ne 0) {
        throw "Path is not a Git repository: $RepositoryPath"
    }
}

function Commit-And-Push {
    param(
        [string]$Name,
        [string]$RepositoryPath,
        [string]$Message,
        [string]$TargetBranch
    )

    Write-Host ""
    Write-Host "Processing $Name" -ForegroundColor Cyan
    Write-Host $RepositoryPath -ForegroundColor DarkGray

    Assert-GitRepository $RepositoryPath

    $currentBranch = (& git -C $RepositoryPath branch --show-current).Trim()

    if ([string]::IsNullOrWhiteSpace($currentBranch)) {
        throw "$Name is in detached HEAD state."
    }

    if ($currentBranch -ne $TargetBranch) {
        Invoke-Git $RepositoryPath @("checkout", $TargetBranch)
    }

    Invoke-Git $RepositoryPath @("pull", "--rebase", "origin", $TargetBranch)

    $status = & git -C $RepositoryPath status --porcelain

    if (-not [string]::IsNullOrWhiteSpace(($status -join "`n"))) {
        Invoke-Git $RepositoryPath @("add", "--all")
        Invoke-Git $RepositoryPath @("commit", "-m", "$Message - $Name")
    }
    else {
        Write-Host "No local changes to commit." -ForegroundColor Yellow
    }

    Invoke-Git $RepositoryPath @("push", "origin", $TargetBranch)
}

try {
    foreach ($repo in $Repositories) {
        Commit-And-Push `
            -Name $repo.Name `
            -RepositoryPath $repo.Path `
            -Message $CommitMessage `
            -TargetBranch $Branch
    }

    Write-Host ""
    Write-Host "Updating parent platform repository" -ForegroundColor Magenta

    Assert-GitRepository $PlatformRoot

    $platformBranch = (& git -C $PlatformRoot branch --show-current).Trim()

    if ([string]::IsNullOrWhiteSpace($platformBranch)) {
        throw "Platform repository is in detached HEAD state."
    }

    if ($platformBranch -ne $Branch) {
        Invoke-Git $PlatformRoot @("checkout", $Branch)
    }

    Invoke-Git $PlatformRoot @("pull", "--rebase", "origin", $Branch)

    $platformStatus = & git -C $PlatformRoot status --porcelain

    if (-not [string]::IsNullOrWhiteSpace(($platformStatus -join "`n"))) {
        Invoke-Git $PlatformRoot @("add", "--all")
        Invoke-Git $PlatformRoot @("commit", "-m", "$CommitMessage - platform")
    }
    else {
        Write-Host "No platform or submodule pointer changes to commit." -ForegroundColor Yellow
    }

    Invoke-Git $PlatformRoot @("push", "origin", $Branch)

    Write-Host ""
    Write-Host "All repositories were processed successfully." -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
