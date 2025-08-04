module ui.manageappidwindow;

import core.stdcpp.new_: cpp_new;
import core.thread;

import std.datetime;
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
alias AppId = server.developersession.AppId;
alias DeveloperTeam = server.developersession.DeveloperTeam;
alias ListAppIdsResponse = server.developersession.ListAppIdsResponse;
alias iOS = server.developersession.iOS;

alias ManageAppIdWindowUI = UIStruct!"manageappidwindow.ui";

class ManageAppIdWindow: QDialog {
    mixin(Q_OBJECT_D);

    ManageAppIdWindowUI* ui;
    DeveloperSession session;
    DeveloperTeam currentTeam;
    
    this(QWidget parent, DeveloperSession session) {
        super(parent);
        this.session = session;
        
        ui = cpp_new!ManageAppIdWindowUI();
        ui.setupUi(this);
        
        setWindowTitle("Manage App IDs");
        setModal(true);
        resize(600, 400);
        
        // Connect signals
        QObject.connect(ui.refreshButton.signal!"clicked", this.slot!"refreshAppIds");
        QObject.connect(ui.closeButton.signal!"clicked", this.slot!"accept");
        
        // Load app IDs
        refreshAppIds();
    }
    
    @QSlot
    void refreshAppIds() {
        ui.appIdList.clear();
        ui.statusLabel.setText(*cpp_new!QString("Loading App IDs..."));
        setControlsEnabled(false);
        
        // Load app IDs in background thread
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
                auto appIdsResponse = session.listAppIds!iOS(currentTeam).unwrap();
                
                runInUIThread({
                    ui.statusLabel.setText(*cpp_new!QString(format!"Found %d App IDs"(appIdsResponse.appIds.length)));
                    
                    foreach (appId; appIdsResponse.appIds) {
                        addAppIdToList(appId);
                    }
                    
                    setControlsEnabled(true);
                });
                
            } catch (Exception ex) {
                auto log = getLogger();
                log.errorF!"Failed to load App IDs: %s"(ex.msg);
                
                runInUIThread({
                    ui.statusLabel.setText(*cpp_new!QString("Failed to load App IDs: " ~ ex.msg));
                    setControlsEnabled(true);
                });
            }
        }).start();
    }
    
private:
    void addAppIdToList(AppId appId) {
        auto widget = cpp_new!QWidget();
        auto layout = cpp_new!QVBoxLayout(widget);
        
        // App ID name and identifier
        auto nameLabel = cpp_new!QLabel(QString(appId.name));
        nameLabel.setStyleSheet(*cpp_new!QString("font-weight: bold; font-size: 14px;"));
        layout.addWidget(nameLabel);
        
        auto identifierLabel = cpp_new!QLabel(QString(appId.identifier));
        identifierLabel.setStyleSheet(*cpp_new!QString("color: #666; font-size: 12px;"));
        layout.addWidget(identifierLabel);
        
        // Expiration date
        auto expirationLabel = cpp_new!QLabel(QString("Expires: " ~ appId.expirationDate.toSimpleString()));
        expirationLabel.setStyleSheet(*cpp_new!QString("color: #888; font-size: 11px;"));
        layout.addWidget(expirationLabel);
        
        // Action buttons
        auto buttonLayout = cpp_new!QHBoxLayout();
        
        auto manageFeaturesButton = cpp_new!QPushButton(QString("Manage Features"));
        manageFeaturesButton.setEnabled(false); // Not implemented yet
        manageFeaturesButton.setToolTip(*cpp_new!QString("Not implemented yet"));
        buttonLayout.addWidget(manageFeaturesButton);
        
        auto deleteButton = cpp_new!QPushButton(QString("Delete"));
        QObject.connect(deleteButton.signal!"clicked", [this, appId]() {
            deleteAppId(appId);
        });
        buttonLayout.addWidget(deleteButton);
        
        buttonLayout.addStretch();
        layout.addLayout(buttonLayout);
        
        // Add to list
        auto listItem = cpp_new!QListWidgetItem();
        listItem.setSizeHint(widget.sizeHint());
        ui.appIdList.addItem(listItem);
        ui.appIdList.setItemWidget(listItem, widget);
    }
    
    void deleteAppId(AppId appId) {
        auto result = QMessageBox.question(
            this,
            *cpp_new!QString("Delete App ID"),
            *cpp_new!QString(format!"Are you sure you want to delete the App ID '%s'?\n\nThis action cannot be undone."(appId.name)),
            QMessageBox.StandardButtons(QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No),
            QMessageBox.StandardButton.No
        );
        
        if (result != QMessageBox.StandardButton.Yes) {
            return;
        }
        
        ui.statusLabel.setText(*cpp_new!QString("Deleting App ID..."));
        setControlsEnabled(false);
        
        new Thread({
            try {
                session.deleteAppId!iOS(currentTeam, appId).unwrap();
                
                runInUIThread({
                    ui.statusLabel.setText(*cpp_new!QString("App ID deleted successfully."));
                    refreshAppIds();
                });
                
            } catch (Exception ex) {
                auto log = getLogger();
                log.errorF!"Failed to delete App ID: %s"(ex.msg);
                
                runInUIThread({
                    ui.statusLabel.setText(*cpp_new!QString("Failed to delete App ID: " ~ ex.msg));
                    setControlsEnabled(true);
                });
            }
        }).start();
    }
    
    void setControlsEnabled(bool enabled) {
        ui.refreshButton.setEnabled(enabled);
        ui.appIdList.setEnabled(enabled);
    }
    
    // Use the proper Qt thread utilities
    // (runInUIThread is now imported from ui.qtthreadutils)
}
