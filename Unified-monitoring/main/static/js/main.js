document.addEventListener('DOMContentLoaded', function() {
    // Service start buttons
    const startServiceButtons = document.querySelectorAll('.start-service-btn, .retry-btn');
    startServiceButtons.forEach(button => {
        button.addEventListener('click', function() {
            const serviceName = this.getAttribute('data-service');
            startService(serviceName);
        });
    });

    // Notification close button
    const notificationClose = document.getElementById('notification-close');
    if (notificationClose) {
        notificationClose.addEventListener('click', function() {
            hideNotification();
        });
    }

    // For demonstration purposes, check status of services periodically
    if (document.querySelector('.status-indicator')) {
        setInterval(checkServiceStatus, 10000);
    }
});

function startService(serviceName) {
    showNotification('Starting service...');
    
    fetch('/start_service/' + serviceName, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
        }
    })
    .then(response => response.json())
    .then(data => {
        if (data.success) {
            showNotification('Service started successfully!', 'success');
            if (data.redirect) {
                window.location.href = data.redirect;
            }
        } else {
            showNotification('Failed to start service: ' + data.message, 'error');
        }
    })
    .catch(error => {
        showNotification('Error: ' + error, 'error');
    });
}

function checkServiceStatus() {
    const statusIndicator = document.querySelector('.status-indicator');
    if (!statusIndicator) return;
    
    const serviceName = document.querySelector('.detail-value:nth-child(2)').textContent.trim();
    
    fetch('/service_status/' + serviceName)
        .then(response => response.json())
        .then(data => {
            if (data.status === 'running') {
                statusIndicator.classList.add('active');
                statusIndicator.classList.remove('inactive');
                statusIndicator.querySelector('.status-text').textContent = 'Running';
            } else {
                statusIndicator.classList.add('inactive');
                statusIndicator.classList.remove('active');
                statusIndicator.querySelector('.status-text').textContent = 'Stopped';
            }
        })
        .catch(error => {
            console.error('Error checking service status:', error);
        });
}

function showNotification(message, type = 'info') {
    const notification = document.getElementById('notification');
    const notificationMessage = document.getElementById('notification-message');
    
    if (notification && notificationMessage) {
        notificationMessage.textContent = message;
        notification.className = 'notification';
        
        if (type === 'success') {
            notification.style.backgroundColor = '#2ecc71';
        } else if (type === 'error') {
            notification.style.backgroundColor = '#e74c3c';
        } else {
            notification.style.backgroundColor = '#3498db';
        }
        
        setTimeout(hideNotification, 5000);
    }
}

function hideNotification() {
    const notification = document.getElementById('notification');
    if (notification) {
        notification.classList.add('hidden');
    }
}