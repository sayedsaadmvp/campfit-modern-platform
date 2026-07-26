CREATE USER core_user WITH PASSWORD 'Test123';
CREATE USER adventure_user WITH PASSWORD 'Test123';
CREATE USER analytics_user WITH PASSWORD 'Test123';

GRANT ALL PRIVILEGES ON DATABASE campfit_core TO core_user;
GRANT ALL PRIVILEGES ON DATABASE campfit_adventure TO adventure_user;
GRANT CONNECT ON DATABASE campfit_analytics TO analytics_user;
