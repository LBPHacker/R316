#pragma once

#include <stdexcept>

namespace r3emu::utility
{
	template<class derived>
	class singleton
	{
		static derived *instance;

	protected:
		singleton()
		{
			if (instance)
			{
				throw std::runtime_error("singleton ctor called twice");
			}
			instance = static_cast<derived *>(this);
		}

		~singleton()
		{
			instance = nullptr;
		}

	public:
		static derived &ref()
		{
			return *instance;
		}
	};

	template<class derived>
	derived *singleton<derived>::instance = nullptr;
}
