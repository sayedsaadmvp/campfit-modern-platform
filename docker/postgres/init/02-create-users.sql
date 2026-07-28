CREATE USER core_user WITH PASSWORD 'Test123';
CREATE USER adventure_user WITH PASSWORD 'Test123';
CREATE USER analytics_user WITH PASSWORD 'Test123';

ALTER DATABASE campfit_core OWNER TO core_user;
ALTER DATABASE campfit_adventure OWNER TO adventure_user;
GRANT CONNECT ON DATABASE campfit_analytics TO analytics_user;
