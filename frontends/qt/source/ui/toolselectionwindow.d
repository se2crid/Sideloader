module ui.toolselectionwindow;

import core.stdcpp.new_: cpp_new;

import std.format;

import slf4d;

import qt.core.namespace;
import qt.core.object;
import qt.core.string;
import qt.helpers;
import qt.widgets.dialog;
import qt.widgets.label;
import qt.widgets.listwidget;
import qt.widgets.pushbutton;
import qt.widgets.ui;
import qt.widgets.widget;
import qt.widgets.boxlayout;
import qt.widgets.messagebox;

import imobiledevice;
import tools;

alias ToolSelectionWindowUI = UIStruct!"toolselectionwindow.ui";

class ToolSelectionWindow: QDialog {
    mixin(Q_OBJECT_D);

    ToolSelectionWindowUI* ui;
    iDevice device;
    Tool[] availableTools;
    
    this(QWidget parent, iDevice device) {
        super(parent);
        this.device = device;
        
        ui = cpp_new!ToolSelectionWindowUI();
        ui.setupUi(this);
        
        setWindowTitle("Additional Tools");
        setModal(true);
        resize(500, 400);
        
        // Connect signals
        QObject.connect(ui.runButton.signal!"clicked", this.slot!"runSelectedTool");
        QObject.connect(ui.closeButton.signal!"clicked", this.slot!"accept");
        QObject.connect(ui.toolList.signal!"itemSelectionChanged", this.slot!"updateRunButton");
        
        // Load available tools
        loadTools();
    }
    
    @QSlot
    void runSelectedTool() {
        auto selectedItems = ui.toolList.selectedItems();
        if (selectedItems.length == 0) {
            return;
        }
        
        int toolIndex = ui.toolList.row(selectedItems[0]);
        if (toolIndex < 0 || toolIndex >= availableTools.length) {
            return;
        }
        
        Tool tool = availableTools[toolIndex];
        
        // Check if tool has diagnostic issues
        if (tool.diagnostic) {
            QMessageBox.warning(
                this,
                *cpp_new!QString("Tool Unavailable"),
                *cpp_new!QString(tool.diagnostic)
            );
            return;
        }
        
        // Run the tool
        ui.statusLabel.setText(*cpp_new!QString("Running tool: " ~ tool.name));
        ui.runButton.setEnabled(false);
        
        try {
            tool.run((message, canCancel) {
                alias StandardButton = QMessageBox.StandardButton;
                alias StandardButtons = QMessageBox.StandardButtons;
                
                StandardButton button = QMessageBox.question(
                    this,
                    *cpp_new!QString(tool.name),
                    *cpp_new!QString(message),
                    StandardButtons(StandardButton.Ok | (canCancel ? StandardButton.Cancel : StandardButton.NoButton))
                );
                
                return button == StandardButton.Cancel;
            });
            
            ui.statusLabel.setText(*cpp_new!QString("Tool completed successfully."));
            
        } catch (Exception ex) {
            auto log = getLogger();
            log.errorF!"Tool execution failed: %s"(ex.msg);
            
            QMessageBox.critical(
                this,
                *cpp_new!QString("Tool Error"),
                *cpp_new!QString("Tool execution failed: " ~ ex.msg)
            );
            
            ui.statusLabel.setText(*cpp_new!QString("Tool execution failed."));
        }
        
        ui.runButton.setEnabled(true);
    }
    
    @QSlot
    void updateRunButton() {
        auto selectedItems = ui.toolList.selectedItems();
        bool hasSelection = selectedItems.length > 0;
        
        if (hasSelection) {
            int toolIndex = ui.toolList.row(selectedItems[0]);
            if (toolIndex >= 0 && toolIndex < availableTools.length) {
                Tool tool = availableTools[toolIndex];
                ui.runButton.setEnabled(tool.diagnostic is null);
                return;
            }
        }
        
        ui.runButton.setEnabled(false);
    }
    
private:
    void loadTools() {
        ui.toolList.clear();
        availableTools = toolList(device);
        
        foreach (tool; availableTools) {
            auto item = cpp_new!QListWidgetItem();
            
            // Create custom widget for tool item
            auto widget = cpp_new!QWidget();
            auto layout = cpp_new!QVBoxLayout(widget);
            
            // Tool name
            auto nameLabel = cpp_new!QLabel(QString(tool.name));
            nameLabel.setStyleSheet(*cpp_new!QString("font-weight: bold; font-size: 14px;"));
            layout.addWidget(nameLabel);
            
            // Tool description (if available)
            if (tool.description.length > 0) {
                auto descLabel = cpp_new!QLabel(QString(tool.description));
                descLabel.setStyleSheet(*cpp_new!QString("color: #666; font-size: 12px;"));
                descLabel.setWordWrap(true);
                layout.addWidget(descLabel);
            }
            
            // Diagnostic message (if any)
            if (tool.diagnostic) {
                auto diagLabel = cpp_new!QLabel(QString("⚠ " ~ tool.diagnostic));
                diagLabel.setStyleSheet(*cpp_new!QString("color: #e74c3c; font-size: 11px;"));
                diagLabel.setWordWrap(true);
                layout.addWidget(diagLabel);
            }
            
            item.setSizeHint(widget.sizeHint());
            ui.toolList.addItem(item);
            ui.toolList.setItemWidget(item, widget);
        }
        
        ui.statusLabel.setText(*cpp_new!QString(format!"Found %d tools"(availableTools.length)));
        updateRunButton();
    }
}
