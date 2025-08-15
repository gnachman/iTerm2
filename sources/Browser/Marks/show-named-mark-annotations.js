(function() {
    console.log("[show named mark annotations] starting");

    // Include mark location utilities
    {{INCLUDE:mark-locator.js}}

    // Remove any existing annotations
    var existingContainer = document.getElementById('iterm-mark-annotations');
    if (existingContainer) {
        existingContainer.remove();
    }

    var marks = {{MARKS_JSON}};
    var sessionSecret = "{{SECRET}}";
    if (!marks || marks.length === 0) {
        return false;
    }

    // Create container for annotations
    var container = document.createElement('div');
    container.id = 'iterm-mark-annotations';
    container.style.cssText = `
        position: absolute;
        top: 0;
        right: 0;
        width: 200px;
        height: 100%;
        pointer-events: none;
        z-index: 10000;
        padding: 20px 10px;
        box-sizing: border-box;
    `;


    // Function to add annotation UI (only handles DOM creation and event handlers)
    function addAnnotation(mark, documentPosition, element, container, sessionSecret) {

        // Create annotation container
        var annotation = document.createElement('div');
        annotation.className = 'iterm-mark-annotation';
        annotation.dataset.markGuid = mark.guid;
        annotation.dataset.y = mark.y;
        // Store mark data for position updates
        if (mark.xpath) {
            annotation.dataset.markXpath = mark.xpath;
        }
        if (mark.offsetY !== undefined) {
            annotation.dataset.markOffsetY = mark.offsetY;
        }
        if (mark.textFragment) {
            annotation.dataset.markTextFragment = mark.textFragment;
        }
        console.log(`[show named mark annotations] Add mark with xpath=${mark.xpath} textFragment=${mark.textFragment} y=${mark.y}`);
        annotation.style.cssText = `
            position: absolute;
            right: 0;
            top: ${documentPosition}px;
            background: rgba(255, 215, 0, 0.9);
            color: #333;
            font-size: 12px;
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            border-radius: 0 4px 4px 0;
            cursor: pointer;
            pointer-events: auto;
            transform: translateY(-50%);
            clip-path: polygon(15px 0%, 100% 0%, 100% 100%, 15px 100%, 0% 50%);
            transition: all 0.2s ease;
        `;

        // Create collapsed view (just the mark name)
        var collapsedView = document.createElement('div');
        collapsedView.className = 'iterm-mark-collapsed';
        collapsedView.style.cssText = `
            padding: 6px 12px 6px 20px;
            font-weight: 500;
            min-width: 120px;
            max-width: 200px;
            word-wrap: break-word;
        `;
        collapsedView.textContent = mark.name;
        collapsedView.title = 'Click to expand and edit name';

        // Create expanded view (input for name)
        var expandedView = document.createElement('div');
        expandedView.className = 'iterm-mark-expanded';
        expandedView.style.cssText = `
            display: none;
            padding: 8px 12px 8px 20px;
            min-width: 250px;
            max-width: 350px;
        `;

        var markTitle = document.createElement('div');
        markTitle.style.cssText = `
            font-weight: 600;
            margin-bottom: 6px;
            color: #333;
            display: none;
        `;
        markTitle.textContent = mark.name;

        var input = document.createElement('input');
        input.type = 'text';
        input.value = mark.name || '';
        input.placeholder = 'Enter mark name';
        input.style.cssText = `
            width: 100%;
            height: 30px;
            border: 1px solid #ddd;
            border-radius: 3px;
            padding: 6px;
            font-family: inherit;
            font-size: 11px;
            margin-bottom: 6px;
            background: white;
        `;

        var buttonContainer = document.createElement('div');
        buttonContainer.style.cssText = `
            display: flex;
            gap: 6px;
            justify-content: flex-end;
        `;

        var saveButton = document.createElement('button');
        saveButton.textContent = 'Save';
        saveButton.style.cssText = `
            padding: 4px 8px;
            font-size: 10px;
            line-height: 1;
            border: none;
            border-radius: 3px;
            background: #007acc;
            color: white;
            cursor: pointer;
            height: 22px;
            display: flex;
            align-items: center;
            justify-content: center;
        `;

        var deleteButton = document.createElement('button');
        deleteButton.textContent = 'Delete';
        deleteButton.style.cssText = `
            padding: 4px 8px;
            font-size: 10px;
            line-height: 1;
            border: none;
            border-radius: 3px;
            background: #dc3545;
            color: white;
            cursor: pointer;
            height: 22px;
            display: flex;
            align-items: center;
            justify-content: center;
        `;

        var collapseButton = document.createElement('button');
        collapseButton.textContent = 'Close';
        collapseButton.style.cssText = `
            padding: 4px 8px;
            font-size: 10px;
            line-height: 1;
            border: 1px solid #ccc;
            border-radius: 3px;
            background: white;
            color: #333;
            cursor: pointer;
            height: 22px;
            display: flex;
            align-items: center;
            justify-content: center;
        `;

        expandedView.appendChild(markTitle);
        expandedView.appendChild(input);
        buttonContainer.appendChild(saveButton);
        buttonContainer.appendChild(deleteButton);
        buttonContainer.appendChild(collapseButton);
        expandedView.appendChild(buttonContainer);

        annotation.appendChild(collapsedView);
        annotation.appendChild(expandedView);

        // Add Enter key handler to input for quick save
        input.addEventListener('keydown', function(e) {
            if (e.key === 'Enter') {
                e.preventDefault();
                e.stopPropagation();
                saveButton.click(); // Trigger the save button click
            }
        });

        // Add click handler to expand
        collapsedView.addEventListener('click', function(e) {
            e.preventDefault();
            e.stopPropagation();
            collapsedView.style.display = 'none';
            expandedView.style.display = 'block';
            annotation.style.clipPath = 'polygon(15px 0%, 100% 0%, 100% 100%, 15px 100%, 0% 50%)';
            input.focus();
        });

        // Add click handler to delete
        deleteButton.addEventListener('click', function(e) {
            e.preventDefault();
            e.stopPropagation();

            // Send message to Swift to delete the mark
            try {
                window.webkit.messageHandlers.iTerm2NamedMarkUpdate.postMessage({
                    guid: mark.guid,
                    delete: true,
                    sessionSecret: sessionSecret
                });
            } catch (error) {
                console.log('Error deleting mark:', error);
            }

            // Remove the annotation from the UI immediately
            annotation.remove();
        });

        // Add click handler to collapse
        collapseButton.addEventListener('click', function(e) {
            e.preventDefault();
            e.stopPropagation();
            expandedView.style.display = 'none';
            collapsedView.style.display = 'block';
        });

        // Add save handler
        saveButton.addEventListener('click', function(e) {
            e.preventDefault();
            e.stopPropagation();

            // Send message to Swift to save the name
            try {
                window.webkit.messageHandlers.iTerm2NamedMarkUpdate.postMessage({
                    guid: mark.guid,
                    name: input.value,
                    sessionSecret: sessionSecret
                });
            } catch (error) {
                console.log('Error saving mark name:', error);
            }

            // Update the mark data and UI
            mark.name = input.value;
            collapsedView.textContent = input.value; // Update the collapsed view to show new name

            // Collapse the view
            expandedView.style.display = 'none';
            collapsedView.style.display = 'block';
        });

        container.appendChild(annotation);
    }

    marks.forEach(function(mark) {
        try {
            var locationInfo = locateMark(mark);
            addAnnotation(mark, locationInfo.documentPosition, locationInfo.element, container, sessionSecret);
        } catch (error) {
            console.log('Error creating annotation for mark:', mark.name, error);
        }
    });

    // Only add container if it has annotations
    if (container.children.length > 0) {
        document.body.appendChild(container);
    }
    return true;
})();
