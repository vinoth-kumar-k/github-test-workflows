<%@ Page Language="vb" AutoEventWireup="false" CodeBehind="Default.aspx.vb" Inherits="VBNetApp._Default" %>

<!DOCTYPE html>

<html xmlns="http://www.w3.org/1999/xhtml">
<head runat="server">
    <title>VB.NET Web Forms POC</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            max-width: 800px;
            margin: 50px auto;
            padding: 20px;
            background-color: #f5f5f5;
        }
        .container {
            background-color: white;
            padding: 30px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        h1 {
            color: #333;
        }
        .info {
            margin: 20px 0;
            padding: 15px;
            background-color: #e3f2fd;
            border-left: 4px solid #2196f3;
        }
        .button {
            background-color: #2196f3;
            color: white;
            padding: 10px 20px;
            border: none;
            border-radius: 4px;
            cursor: pointer;
            font-size: 14px;
        }
        .button:hover {
            background-color: #1976d2;
        }
        .result {
            margin-top: 20px;
            padding: 15px;
            background-color: #f1f8e9;
            border-left: 4px solid #8bc34a;
        }
    </style>
</head>
<body>
    <form id="form1" runat="server">
        <div class="container">
            <h1>VB.NET Web Forms Application</h1>

            <div class="info">
                <h3>GitHub Actions CI/CD POC</h3>
                <p>This is a sample ASP.NET Web Forms application built with VB.NET (.NET Framework 4.8)</p>
                <p><strong>Deployment Target:</strong> Azure Windows VM with IIS</p>
                <p><strong>CI/CD Pipeline:</strong> GitHub Actions</p>
            </div>

            <div>
                <h3>Test the Application</h3>
                <asp:Button ID="btnTest" runat="server" Text="Click Me!" CssClass="button" OnClick="btnTest_Click" />

                <asp:Panel ID="pnlResult" runat="server" Visible="False" CssClass="result">
                    <h4>Result:</h4>
                    <asp:Label ID="lblMessage" runat="server" Text=""></asp:Label>
                    <br /><br />
                    <asp:Label ID="lblServerInfo" runat="server" Text=""></asp:Label>
                    <br />
                    <asp:Label ID="lblTimestamp" runat="server" Text=""></asp:Label>
                </asp:Panel>
            </div>

            <div class="info" style="margin-top: 30px;">
                <h4>Deployment Information</h4>
                <p><strong>Application Version:</strong> <%= GetAppVersion() %></p>
                <p><strong>Environment:</strong> <%= GetEnvironment() %></p>
            </div>
        </div>
    </form>
</body>
</html>
