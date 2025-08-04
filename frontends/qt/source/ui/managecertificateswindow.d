module ui.managecertificateswindow;

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
import qt.widgets.listwidget;
import qt.widgets.pushbutton;
import qt.widgets.ui;
import qt.widgets.widget;
import qt.widgets.boxlayout;
import qt.widgets.messagebox;

import server.developersession;
import ui.qtthreadutils;

// Import the types we need
alias DeveloperTeam = server.developersession.DeveloperTeam;
alias DevelopmentCertificate = server.developersession.DevelopmentCertificate;
alias iOS = server.developersession.iOS;

alias ManageCertificatesWindowUI = UIStruct!"managecertificateswindow.ui";

class ManageCertificatesWindow: QDialog {
    mixin(Q_OBJECT_D);

    ManageCertificatesWindowUI* ui;
    DeveloperSession session;
    DeveloperTeam currentTeam;
    
    this(QWidget parent, DeveloperSession session) {
        super(parent);
        this.session = session;
        
        ui = cpp_new!ManageCertificatesWindowUI();
        ui.setupUi(this);
        
        setWindowTitle(*cpp_new!QString("Manage Certificates"));
        setModal(true);
        resize(600, 400);
        
        // Connect signals
        QObject.connect(ui.refreshButton.signal!"clicked", this.slot!"refreshCertificates");
        QObject.connect(ui.closeButton.signal!"clicked", this.slot!"accept");
        
        // Load certificates
        refreshCertificates();
    }
    
    @QSlot
    void refreshCertificates() {
        ui.certificateList.clear();
        ui.statusLabel.setText(*cpp_new!QString("Loading certificates..."));
        setControlsEnabled(false);
        
        // Load certificates in background thread
        new Thread({
            try {
                auto teams = session.listTeams().unwrap();
                if (teams.length == 0) {
                    runInUIThread({
                        ui.statusLabel.setText(*cpp_new!QString("No teams found."));
                        setControlsEnabled(true);
                    });
                    return;
                }
                
                // Use first team for now
                currentTeam = teams[0];
                auto certificates = session.listAllDevelopmentCerts!iOS(currentTeam).unwrap();
                
                runInUIThread({
                    ui.statusLabel.setText(*cpp_new!QString(format!"Found %d certificates"(certificates.length)));
                    
                    foreach (certificate; certificates) {
                        addCertificateToList(certificate);
                    }
                    
                    setControlsEnabled(true);
                });
                
            } catch (Exception ex) {
                auto log = getLogger();
                log.errorF!"Failed to load certificates: %s"(ex.msg);
                
                runInUIThread({
                    ui.statusLabel.setText(*cpp_new!QString("Failed to load certificates: " ~ ex.msg));
                    setControlsEnabled(true);
                });
            }
        }).start();
    }
    
private:
    void addCertificateToList(DevelopmentCertificate certificate) {
        auto widget = cpp_new!QWidget();
        auto layout = cpp_new!QVBoxLayout(widget);
        
        // Certificate name and machine name
        auto nameLabel = cpp_new!QLabel(QString(certificate.name));
        nameLabel.setStyleSheet(*cpp_new!QString("font-weight: bold; font-size: 14px;"));
        layout.addWidget(nameLabel);
        
        auto machineLabel = cpp_new!QLabel(QString("Machine: " ~ certificate.machineName));
        machineLabel.setStyleSheet(*cpp_new!QString("color: #666; font-size: 12px;"));
        layout.addWidget(machineLabel);
        
        // Certificate ID
        auto idLabel = cpp_new!QLabel(QString("ID: " ~ certificate.certificateId));
        idLabel.setStyleSheet(*cpp_new!QString("color: #888; font-size: 11px;"));
        layout.addWidget(idLabel);
        
        // Action buttons
        auto buttonLayout = cpp_new!QHBoxLayout();
        
        auto downloadButton = cpp_new!QPushButton(QString("Download"));
        downloadButton.setEnabled(false); // Not implemented yet
        downloadButton.setToolTip(*cpp_new!QString("Not implemented yet"));
        buttonLayout.addWidget(downloadButton);
        
        auto revokeButton = cpp_new!QPushButton(QString("Revoke"));
        revokeButton.setStyleSheet(*cpp_new!QString("QPushButton { background-color: #e74c3c; color: white; }"));
        // Capture certificate in a closure
        auto capturedCertificate = certificate;
        QObject.connect(revokeButton.signal!"clicked", delegate() {
            revokeCertificate(capturedCertificate);
        });
        buttonLayout.addWidget(revokeButton);
        
        buttonLayout.addStretch();
        layout.addLayout(buttonLayout);
        
        // Add to list
        auto listItem = cpp_new!QListWidgetItem();
        listItem.setSizeHint(widget.sizeHint());
        ui.certificateList.addItem(listItem);
        ui.certificateList.setItemWidget(listItem, widget);
    }
    
    void revokeCertificate(DevelopmentCertificate certificate) {
        auto result = QMessageBox.question(
            this,
            *cpp_new!QString("Revoke Certificate"),
            *cpp_new!QString(format!"Are you sure you want to revoke the certificate '%s'?\n\nThis action cannot be undone and will invalidate all apps signed with this certificate."(certificate.name)),
            QMessageBox.StandardButtons(QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No),
            QMessageBox.StandardButton.No
        );
        
        if (result != QMessageBox.StandardButton.Yes) {
            return;
        }
        
        ui.statusLabel.setText(*cpp_new!QString("Revoking certificate..."));
        setControlsEnabled(false);
        
        new Thread({
            try {
                session.revokeDevelopmentCert!iOS(currentTeam, certificate).unwrap();
                
                runInUIThread({
                    ui.statusLabel.setText(*cpp_new!QString("Certificate revoked successfully."));
                    refreshCertificates();
                });
                
            } catch (Exception ex) {
                auto log = getLogger();
                log.errorF!"Failed to revoke certificate: %s"(ex.msg);
                
                runInUIThread({
                    ui.statusLabel.setText(*cpp_new!QString("Failed to revoke certificate: " ~ ex.msg));
                    setControlsEnabled(true);
                });
            }
        }).start();
    }
    
    void setControlsEnabled(bool enabled) {
        ui.refreshButton.setEnabled(enabled);
        ui.certificateList.setEnabled(enabled);
    }
    
    // Use the proper Qt thread utilities
    // (runInUIThread is now imported from ui.qtthreadutils)
}
