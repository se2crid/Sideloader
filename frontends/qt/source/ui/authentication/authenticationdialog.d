module ui.authentication.authenticationdialog;

import core.stdcpp.new_: cpp_new;
import core.thread;

import std.concurrency;
import std.format;
import std.sumtype;

import slf4d;

import qt.core.namespace;
import qt.core.object;
import qt.core.string;
import qt.core.thread;
import qt.helpers;
import qt.widgets.dialog;
import qt.widgets.label;
import qt.widgets.lineedit;
import qt.widgets.pushbutton;
import qt.widgets.stackedwidget;
import qt.widgets.ui;
import qt.widgets.widget;
import qt.widgets.boxlayout;

import provision;

import server.appleaccount;
import server.developersession;
import ui.qtthreadutils;

alias DeveloperAction = void delegate(DeveloperSession);

alias AuthenticationDialogUI = UIStruct!"authenticationdialog.ui";

class AuthenticationDialog: QDialog {
    mixin(Q_OBJECT_D);

    AuthenticationDialogUI* ui;
    DeveloperAction successCallback;
    Device device;
    ADI adi;

    // Current authentication state
    Send2FADelegate send2FADelegate;
    Submit2FADelegate submit2FADelegate;
    
    this(DeveloperAction callback, Device device, ADI adi) {
        this.successCallback = callback;
        this.device = device;
        this.adi = adi;
        
        ui = cpp_new!AuthenticationDialogUI();
        ui.setupUi(this);
        
        // Connect signals
        QObject.connect(ui.loginButton.signal!"clicked", this.slot!"performLogin");
        QObject.connect(ui.submitCodeButton.signal!"clicked", this.slot!"submit2FA");
        QObject.connect(ui.backButton.signal!"clicked", this.slot!"goBack");
        QObject.connect(ui.cancelButton.signal!"clicked", this.slot!"reject");
        
        // Set initial state to login page
        ui.stackedWidget.setCurrentIndex(0);
        ui.backButton.setVisible(false);
        
        setWindowTitle("Apple Account Authentication");
        setModal(true);
    }
    
    @QSlot
    void performLogin() {
        string appleId = ui.appleIdEdit.text().toConstWString().to!string();
        string password = ui.passwordEdit.text().toConstWString().to!string();
        
        if (appleId.length == 0 || password.length == 0) {
            setErrorMessage("Please enter both Apple ID and password.");
            return;
        }
        
        // Clear any previous error
        setErrorMessage("");
        
        // Disable UI during login
        setLoginEnabled(false);
        
        // Perform login in background thread
        new Thread({
            try {
                auto loginResponse = DeveloperSession.login(device, adi, appleId, password, (send2FA, submit2FA) {
                    // 2FA required
                    send2FADelegate = send2FA;
                    submit2FADelegate = submit2FA;

                    runInUIThread({
                        show2FAPage();
                    });
                });

                loginResponse.match!(
                    (DeveloperSession session) {
                        // Login successful
                        runInUIThread({
                            completeAuthentication(session);
                        });
                    },
                    (AppleLoginError error) {
                        auto log = getLogger();
                        log.errorF!"Login failed: %s"(error.description);

                        runInUIThread({
                            setErrorMessage(error.description);
                            setLoginEnabled(true);
                        });
                    }
                );

            } catch (Exception ex) {
                auto log = getLogger();
                log.errorF!"Login failed: %s"(ex.msg);

                runInUIThread({
                    setErrorMessage(ex.msg);
                    setLoginEnabled(true);
                });
            }
        }).start();
    }
    
    @QSlot
    void submit2FA() {
        string code = ui.codeEdit.text().toConstWString().to!string();
        
        if (code.length == 0) {
            set2FAErrorMessage("Please enter the verification code.");
            return;
        }
        
        // Clear any previous error
        set2FAErrorMessage("");
        
        // Disable UI during submission
        set2FAEnabled(false);
        
        // Submit 2FA code in background thread
        new Thread({
            try {
                auto response = submit2FADelegate(code);

                response.match!(
                    (Success success) {
                        runInUIThread({
                            // 2FA successful, need to complete login
                            performLoginAfter2FA();
                        });
                    },
                    (ReloginNeeded relogin) {
                        runInUIThread({
                            set2FAErrorMessage("Please try logging in again.");
                            set2FAEnabled(true);
                        });
                    },
                    (AppleLoginError error) {
                        runInUIThread({
                            set2FAErrorMessage(error.description);
                            set2FAEnabled(true);
                        });
                    }
                );

            } catch (Exception ex) {
                auto log = getLogger();
                log.errorF!"2FA submission failed: %s"(ex.msg);

                runInUIThread({
                    set2FAErrorMessage(ex.msg);
                    set2FAEnabled(true);
                });
            }
        }).start();
    }
    
    @QSlot
    void goBack() {
        if (ui.stackedWidget.currentIndex() == 1) {
            // Go back from 2FA to login
            ui.stackedWidget.setCurrentIndex(0);
            ui.backButton.setVisible(false);
            setLoginEnabled(true);
        }
    }
    
private:
    void show2FAPage() {
        ui.stackedWidget.setCurrentIndex(1);
        ui.backButton.setVisible(true);
        ui.codeEdit.clear();
        ui.codeEdit.setFocus();
        set2FAEnabled(true);
        
        // Send 2FA code
        if (send2FADelegate) {
            new Thread({
                try {
                    send2FADelegate();
                } catch (Exception ex) {
                    auto log = getLogger();
                    log.errorF!"Failed to send 2FA code: %s"(ex.msg);
                    
                    runInUIThread({
                        set2FAErrorMessage("Failed to send verification code. Please try again.");
                    });
                }
            }).start();
        }
    }
    
    void completeAuthentication(DeveloperSession session) {
        try {
            successCallback(session);
            accept();
        } catch (Exception ex) {
            auto log = getLogger();
            log.errorF!"Failed to complete authentication: %s"(ex.msg);
            setErrorMessage("Failed to complete authentication: " ~ ex.msg);
            setLoginEnabled(true);
        }
    }

    void performLoginAfter2FA() {
        // After successful 2FA, we need to complete the login process
        // This is typically handled automatically by the DeveloperSession.login method
        // For now, we'll show an error asking the user to try again
        set2FAErrorMessage("2FA successful. Please close this dialog and try logging in again.");
    }
    
    void setErrorMessage(string message) {
        ui.errorLabel.setText(*cpp_new!QString(format!`<span style="color:#e01b24;">%s</span>`(message)));
    }
    
    void set2FAErrorMessage(string message) {
        ui.tfaErrorLabel.setText(*cpp_new!QString(format!`<span style="color:#e01b24;">%s</span>`(message)));
    }
    
    void setLoginEnabled(bool enabled) {
        ui.appleIdEdit.setEnabled(enabled);
        ui.passwordEdit.setEnabled(enabled);
        ui.loginButton.setEnabled(enabled);
    }
    
    void set2FAEnabled(bool enabled) {
        ui.codeEdit.setEnabled(enabled);
        ui.submitCodeButton.setEnabled(enabled);
    }
    
    // Use the proper Qt thread utilities
    // (runInUIThread is now imported from ui.qtthreadutils)

    static void authenticate(QWidget parent, Device device, ADI adi, DeveloperAction callback) {
        auto dialog = new AuthenticationDialog(callback, device, adi);
        dialog.setParent(parent);
        dialog.exec();
    }
}
