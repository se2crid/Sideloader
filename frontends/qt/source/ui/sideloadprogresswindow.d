module ui.sideloadprogresswindow;

import core.stdcpp.new_: cpp_new;
import core.thread;

import std.format;

import slf4d;

import qt.core.namespace;
import qt.core.object;
import qt.core.string;
import qt.core.thread;
import qt.helpers;
import qt.widgets.dialog;
import qt.widgets.label;
import qt.widgets.progressbar;
import qt.widgets.pushbutton;
import qt.widgets.ui;
import qt.widgets.widget;

import imobiledevice;
import server.developersession;
import sideload;
import ui.qtthreadutils;

alias SideloadProgressWindowUI = UIStruct!"sideloadprogresswindow.ui";

class SideloadProgressWindow: QDialog {
    mixin(Q_OBJECT_D);

    SideloadProgressWindowUI* ui;
    bool isCancelled = false;
    
    this(QWidget parent) {
        super(parent);
        
        ui = cpp_new!SideloadProgressWindowUI();
        ui.setupUi(this);
        
        setWindowTitle("Installing Application");
        setModal(true);
        setFixedSize(400, 120);
        
        // Disable close button during installation
        setWindowFlags(windowFlags() & ~Qt.WindowType.WindowCloseButtonHint);
        
        // Connect cancel button
        QObject.connect(ui.cancelButton.signal!"clicked", this.slot!"cancelInstallation");
        
        // Initialize progress
        ui.progressBar.setValue(0);
        ui.statusLabel.setText(*cpp_new!QString("Preparing installation..."));
    }
    
    @QSlot
    void cancelInstallation() {
        isCancelled = true;
        ui.cancelButton.setEnabled(false);
        ui.statusLabel.setText(*cpp_new!QString("Cancelling..."));
    }
    
    @QSlot
    void updateProgress(int percentage, ref const(QString) message) {
        ui.progressBar.setValue(percentage);
        ui.statusLabel.setText(message);
    }
    
    @QSlot
    void installationComplete(bool success, ref const(QString) message) {
        if (success) {
            ui.progressBar.setValue(100);
            ui.statusLabel.setText(*cpp_new!QString("Installation completed successfully!"));
            ui.cancelButton.setText(*cpp_new!QString("Close"));
            ui.cancelButton.setEnabled(true);
            QObject.disconnect(ui.cancelButton.signal!"clicked", this.slot!"cancelInstallation");
            QObject.connect(ui.cancelButton.signal!"clicked", this.slot!"accept");
        } else {
            ui.statusLabel.setText(message);
            ui.cancelButton.setText(*cpp_new!QString("Close"));
            ui.cancelButton.setEnabled(true);
            QObject.disconnect(ui.cancelButton.signal!"clicked", this.slot!"cancelInstallation");
            QObject.connect(ui.cancelButton.signal!"clicked", this.slot!"reject");
        }
    }
    
    static void performSideload(QWidget parent, string configurationPath, 
                               DeveloperSession session, Application iosApp, iDevice device) {
        auto progressWindow = new SideloadProgressWindow(parent);
        progressWindow.show();
        
        // Perform sideloading in background thread
        new Thread({
            try {
                sideloadFull(configurationPath, device, session, iosApp, 
                    (progress, message) {
                        // Update progress in UI thread
                        runInUIThread({
                            if (!progressWindow.isCancelled) {
                                progressWindow.updateProgress(
                                    cast(int)(progress * 100), 
                                    *cpp_new!QString(message)
                                );
                            }
                        });
                        
                        // Check if cancelled
                        return progressWindow.isCancelled;
                    }
                );
                
                // Installation completed successfully
                runInUIThread({
                    if (!progressWindow.isCancelled) {
                        progressWindow.installationComplete(
                            true, 
                            *cpp_new!QString("Installation completed successfully!")
                        );
                    }
                });
                
            } catch (Exception ex) {
                auto log = getLogger();
                log.errorF!"Sideloading failed: %s"(ex.msg);
                
                runInUIThread({
                    progressWindow.installationComplete(
                        false, 
                        *cpp_new!QString("Installation failed: " ~ ex.msg)
                    );
                });
            }
        }).start();
    }
    
private:
    // Use the proper Qt thread utilities
    // (runInUIThread is now imported from ui.qtthreadutils)
}
