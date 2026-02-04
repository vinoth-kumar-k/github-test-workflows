Imports System.Configuration
Imports System.Web.Configuration

Public Class _Default
    Inherits System.Web.UI.Page

    Protected Sub Page_Load(ByVal sender As Object, ByVal e As System.EventArgs) Handles Me.Load
        ' Page load logic
        If Not IsPostBack Then
            ' Initialize page
        End If
    End Sub

    Protected Sub btnTest_Click(sender As Object, e As EventArgs)
        ' Handle button click
        pnlResult.Visible = True

        ' Set message
        lblMessage.Text = "Hello from VB.NET Web Forms! The application is running successfully."

        ' Display server information
        lblServerInfo.Text = String.Format("Server: {0} | .NET Version: {1}",
                                          Environment.MachineName,
                                          Environment.Version.ToString())

        ' Display timestamp
        lblTimestamp.Text = String.Format("Timestamp: {0}",
                                         DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"))
    End Sub

    Protected Function GetAppVersion() As String
        ' Get application version from configuration or assembly
        Try
            Return "1.0.0"
        Catch ex As Exception
            Return "Unknown"
        End Try
    End Function

    Protected Function GetEnvironment() As String
        ' Get environment from configuration
        Try
            Dim envSetting As String = ConfigurationManager.AppSettings("Environment")
            If Not String.IsNullOrEmpty(envSetting) Then
                Return envSetting
            Else
                Return "Development"
            End If
        Catch ex As Exception
            Return "Development"
        End Try
    End Function

End Class
