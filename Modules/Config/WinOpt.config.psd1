@{
  Profile = "BASE"   # BASE | ULTRA

  Features = @{
    WSearch = @{
      BaseEnabled  = $true
      UltraEnabled = $false
    }

    WindowsUpdate = @{
      DisableScheduledStart = $false
    }

    DoH = @{
      EnableTemplates   = $true
      EnforceAdapterDns = $true   # 1.1.1.1 primario + router secondario (split-DNS safe)
    }
  }
}
