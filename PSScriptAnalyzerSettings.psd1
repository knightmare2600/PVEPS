@{
  Severity     = @('Error', 'Warning', 'Information')
  IncludeDefaultRules = $true
  Rules        = @{
    PSUseConsistentIndentation = @{
      Enable              = $true
      IndentationSize     = 2
      Kind                = 'space'
      PipelineIndentation = 'IncreaseIndentationForFirstPipeline'
    }
    PSUseConsistentWhitespace  = @{
      Enable                          = $true
      CheckInnerBrace                 = $true
      CheckOpenBrace                  = $true
      CheckOpenParen                  = $true
      CheckOperator                   = $false
      CheckPipe                       = $true
      CheckSeparator                  = $true
      CheckParameter                  = $false
    }
    PSPlaceOpenBrace           = @{
      Enable             = $true
      OnSameLine         = $true
      NewLineAfter       = $true
      IgnoreOneLineBlock = $true
    }
    PSAvoidUsingCmdletAliases  = @{
      Enable = $true
    }
  }
}
